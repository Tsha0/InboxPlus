import Foundation
import Testing
@testable import PalloRuntime

// MARK: - Workload shape

@Test func representativeWorkloadMeetsApprovedShape() {
    let workload = BenchmarkWorkload.representative(seed: 42)
    #expect(workload.roomCount == 2_000)
    #expect(workload.messageCount >= 100_000)
    #expect(workload.importWorkerCount == 3)
    #expect(workload.liveTrafficCount > 0)
    #expect(workload.timelineReadCount > 0)
    #expect(workload.searchCount > 0)
    #expect(workload.mediaMetadataCount > 0)
}

@Test func reducedWorkloadKeepsEveryDimensionNonEmpty() {
    let workload = BenchmarkWorkload.reduced(seed: 7, rooms: 20, messages: 1_000, importWorkers: 3)
    #expect(workload.roomCount == 20)
    #expect(workload.messageCount == 1_000)
    #expect(workload.importWorkerCount == 3)
    #expect(workload.liveTrafficCount > 0)
    #expect(workload.timelineReadCount > 0)
    #expect(workload.searchCount > 0)
    #expect(workload.mediaMetadataCount > 0)
}

// MARK: - Execution

@Test func everyImportedEventIsReconciledExactly() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 12)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 12, messages: 60, importWorkers: 3)
    )

    #expect(run.reconciliation.missingEventIDs.isEmpty)
    #expect(run.reconciliation.duplicateEventIDs.isEmpty)
    #expect(run.reconciliation.missingRoomIDs.isEmpty)
    #expect(run.importedEventCount == 60)
}

@Test func missingEventFailsReconciliation() async throws {
    // Break caught: a dropped write is invisible unless every expected event is read back.
    let operations = FakeBenchmarkOperations(roomCount: 6, dropEventAtIndex: 3)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 6, messages: 30, importWorkers: 3)
    )

    #expect(run.reconciliation.missingEventIDs.count == 1)
    #expect(!run.reconciliation.isExact)
}

@Test func duplicatedEventFailsReconciliation() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 6, duplicateEventAtIndex: 2)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 6, messages: 30, importWorkers: 3)
    )

    #expect(run.reconciliation.duplicateEventIDs.count == 1)
    #expect(!run.reconciliation.isExact)
}

@Test func importsArePartitionedAcrossExactlyTheConfiguredWorkers() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 20)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 20, messages: 100, importWorkers: 3)
    )

    #expect(run.importPartitionSizes.count == 3)
    #expect(run.importPartitionSizes.reduce(0, +) == 20)
    #expect(run.importPartitionSizes.allSatisfy { $0 > 0 })
}

@Test func everyWorkloadDimensionActuallyRuns() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 12)
    let workload = BenchmarkWorkload.reduced(seed: 7, rooms: 12, messages: 60, importWorkers: 3)
    let run = try await BenchmarkRunner(operations: operations).run(workload)

    #expect(run.samples.warmTimelineReads.count == workload.timelineReadCount)
    #expect(run.samples.searches.count == workload.searchCount)
    #expect(run.samples.mediaMetadata.count == workload.mediaMetadataCount)
    #expect(run.liveTrafficEventCount == workload.liveTrafficCount)
    #expect(await operations.searchCount() == workload.searchCount)
    #expect(await operations.mediaMetadataCount() == workload.mediaMetadataCount)
    // Live traffic reads its own room back to measure visibility, on top of the warm reads.
    #expect(
        await operations.timelineReadCount()
            == workload.timelineReadCount + workload.liveTrafficCount
    )
}

@Test func transactionIdentifiersAreStableAcrossRuns() async throws {
    let first = FakeBenchmarkOperations(roomCount: 8)
    _ = try await BenchmarkRunner(operations: first).run(
        .reduced(seed: 99, rooms: 8, messages: 40, importWorkers: 2)
    )
    let second = FakeBenchmarkOperations(roomCount: 8)
    _ = try await BenchmarkRunner(operations: second).run(
        .reduced(seed: 99, rooms: 8, messages: 40, importWorkers: 2)
    )

    #expect(await first.transactionIdentifiers() == second.transactionIdentifiers())
}

@Test func reconciliationReadsHappenAfterEveryWriterFinishes() async throws {
    // Break caught: reading while imports are still committing under-counts and hides loss.
    let operations = FakeBenchmarkOperations(roomCount: 10)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 10, messages: 50, importWorkers: 3)
    )

    #expect(await operations.sawReadBeforeAllWritesCompleted() == false)
    // Guards the guard: reconciliation must actually have read something back.
    #expect(run.reconciliation.observedEventCount == run.reconciliation.expectedEventCount)
    #expect(run.reconciliation.expectedEventCount > 0)
}

@Test func latencySamplesAreCollectedForEveryMeasuredCategory() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 10)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 10, messages: 50, importWorkers: 3)
    )

    #expect(!run.samples.warmTimelineReads.isEmpty)
    #expect(!run.samples.committedEventVisibility.isEmpty)
    #expect(!run.samples.imports.isEmpty)
}

@Test func anUnrecoverableRequestFailureIsRecorded() async throws {
    let operations = FakeBenchmarkOperations(roomCount: 6, failSendAtIndex: 4)
    let run = try await BenchmarkRunner(operations: operations).run(
        .reduced(seed: 7, rooms: 6, messages: 30, importWorkers: 2)
    )

    #expect(run.unrecoverableFailureCount == 1)
}

// MARK: - Fake operations

private actor FakeBenchmarkOperations: BenchmarkMatrixOperations {
    private let rooms: [String]
    private let dropEventAtIndex: Int?
    private let duplicateEventAtIndex: Int?
    private let failSendAtIndex: Int?

    private var committed: [String: [String]] = [:]
    private var sendIndex = 0
    private var recordedTransactionIdentifiers: [String] = []
    private var writesAtFirstReconciliationRead: Int?
    private var completedWrites = 0
    private var timelineReads = 0
    private var searches = 0
    private var mediaLookups = 0

    init(
        roomCount: Int,
        dropEventAtIndex: Int? = nil,
        duplicateEventAtIndex: Int? = nil,
        failSendAtIndex: Int? = nil
    ) {
        rooms = (0..<roomCount).map { "!room\($0):pallo.localhost" }
        self.dropEventAtIndex = dropEventAtIndex
        self.duplicateEventAtIndex = duplicateEventAtIndex
        self.failSendAtIndex = failSendAtIndex
    }

    func createdRoomIDs() async throws -> [String] { rooms }

    func sendMessage(roomID: String, transactionID: String, body: String) async throws -> String {
        recordedTransactionIdentifiers.append(transactionID)
        let index = sendIndex
        sendIndex += 1
        completedWrites += 1

        if index == failSendAtIndex {
            throw MatrixHTTPError.retriesExhausted(statusCode: 503, attempts: 4)
        }
        let eventID = "$event-\(index)"
        if index == dropEventAtIndex { return eventID }
        committed[roomID, default: []].append(eventID)
        if index == duplicateEventAtIndex {
            committed[roomID, default: []].append(eventID)
        }
        return eventID
    }

    func readTimeline(roomID: String, limit: Int) async throws -> Int {
        timelineReads += 1
        return committed[roomID]?.count ?? 0
    }

    func search(term: String) async throws -> Int {
        searches += 1
        return 0
    }

    func mediaMetadata(index: Int) async throws -> Int {
        mediaLookups += 1
        return 0
    }

    func eventIDs(inRoom roomID: String) async throws -> [String] {
        // Record the write count observed by the first reconciliation read; if any write lands
        // afterwards, reconciliation started while writers were still committing.
        if writesAtFirstReconciliationRead == nil {
            writesAtFirstReconciliationRead = completedWrites
        }
        return committed[roomID] ?? []
    }

    func transactionIdentifiers() -> [String] { recordedTransactionIdentifiers.sorted() }
    func timelineReadCount() -> Int { timelineReads }
    func searchCount() -> Int { searches }
    func mediaMetadataCount() -> Int { mediaLookups }
    func sawReadBeforeAllWritesCompleted() -> Bool {
        guard let writesAtFirstReconciliationRead else { return false }
        return writesAtFirstReconciliationRead != completedWrites
    }
}
