import Foundation
import PalloRuntime

func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func describe(_ snapshot: RuntimeSnapshot) -> String {
    var fields = ["phase=\(snapshot.phase.rawValue)"]
    if let port = snapshot.loopbackPort { fields.append("port=\(port)") }
    if let identity = snapshot.processIdentity { fields.append("pid=\(identity.processIdentifier)") }
    fields.append("restarts=\(snapshot.restartCount)")
    if snapshot.processIdentity != nil, let health = snapshot.lastHealthResult {
        fields.append("health=\(health)")
    }
    if let error = snapshot.lastError { fields.append("error=\(error)") }
    return fields.joined(separator: " ")
}

func makeService(profile: String) throws -> RuntimeProfileService {
    let root = try RuntimeProfileService.developerRuntimeRoot()
    let paths = try RuntimePaths(root: root, profileName: profile)
    return RuntimeProfileService(paths: paths, packageRoot: RuntimeProfileService.resolvedPackageRoot())
}

func execute(_ command: RuntimeCommand) async throws -> String {
    let service = try makeService(profile: command.profile)
    // `status` only observes, so it must never contend with the session that owns the profile.
    let lock: ProfileLock?
    do {
        lock = try command.observesOnly ? nil : service.acquireProfileLock()
    } catch ProfileLockError.alreadyLocked {
        throw RuntimeProfileError.profileLockedByAnotherSession
    }
    defer { _ = lock }

    switch command {
    case let .bootstrap(_, python):
        let receipt = try await service.bootstrap(python: URL(fileURLWithPath: python))
        return """
        prepared profile '\(command.profile)' \
        python=\(receipt.pythonVersion) synapse=\(receipt.synapseVersion) \
        packages=\(receipt.installedPackages.count)
        """
    case .start:
        let monitor = InterruptMonitor()
        let stopped = try await service.runForegroundSession(
            interrupt: { await monitor.wait() },
            onReady: { snapshot in
                print(describe(snapshot))
                print("supervising; press Ctrl-C to stop")
                // The session blocks indefinitely, so a redirected stdout must not stay buffered.
                fflush(stdout)
            }
        )
        return describe(stopped)
    case .status:
        return describe(try await service.status())
    case .stop:
        return describe(try await service.stop())
    case let .verify(_, options):
        if options.simulateDataLoss {
            guard let backup = options.restoreBackup else {
                throw RuntimeCommandError.missingOption("--restore")
            }
            let recovery = try await service.verifyRecovery(
                name: backup,
                seed: BenchmarkCLIOptions.defaultSeed
            )
            guard recovery.succeeded else {
                throw VerificationFailed(
                    summary: """
                    recovery failed: integrity=\(recovery.integrity) \
                    rooms=\(recovery.roomCount) events=\(recovery.eventCount) \
                    acceptedNewWrite=\(recovery.acceptedNewWrite)
                    """
                )
            }
            return """
            recovered '\(command.profile)' from '\(backup)' \
            integrity=\(recovery.integrity) rooms=\(recovery.roomCount) \
            events=\(recovery.eventCount) accepted-new-write=\(recovery.acceptedNewWrite)
            """
        }
        if let reportName = options.reportName {
            let verification = try service.verifyReport(named: reportName)
            let decision = verification.decision == .retainSQLiteProvisionally
                ? "Retain SQLite provisionally"
                : "Require PostgreSQL"
            var summary = """
            verified report '\(verification.name)' \
            samples=\(verification.sampleCount) decision: \(decision)
            """
            for gate in verification.failingGates {
                summary += "\n  - failed gate: \(gate)"
            }
            return summary
        }
        if let rooms = options.fixtureRooms {
            let verification = try await service.verifyFixtures(
                seed: BenchmarkCLIOptions.defaultSeed,
                rooms: rooms
            )
            guard verification.reconciledExactly else {
                throw VerificationFailed(
                    summary: """
                    fixture reconciliation failed: requested=\(verification.requestedRooms) \
                    created=\(verification.createdRooms) \
                    reconciled=\(verification.reconciledRooms) \
                    missing=\(verification.missingRooms.count)
                    """
                )
            }
            return """
            verified profile '\(command.profile)' \
            rooms=\(verification.reconciledRooms)/\(verification.requestedRooms) reconciled exactly
            """
        }
        let receipt = try service.verifyPreparedRuntime()
        return """
        verified profile '\(command.profile)' \
        python=\(receipt.pythonVersion) synapse=\(receipt.synapseVersion) \
        packages=\(receipt.installedPackages.count) configuration=loopback-only
        """
    case let .benchmark(_, options):
        let report = try await service.runBenchmark(
            BenchmarkWorkload.reduced(
                seed: options.seed,
                rooms: options.rooms,
                messages: options.messages,
                importWorkers: options.importWorkers
            )
        )
        let run = report.run
        let decision = report.verdict.decision == .retainSQLiteProvisionally
            ? "Retain SQLite provisionally"
            : "Require PostgreSQL"
        var summary = """
        benchmark '\(command.profile)' rooms=\(run.workload.roomCount) \
        imported=\(run.importedEventCount) live=\(run.liveTrafficEventCount) \
        missing=\(run.reconciliation.missingEventIDs.count) \
        duplicates=\(run.reconciliation.duplicateEventIDs.count) \
        failures=\(run.unrecoverableFailureCount) \
        integrity=\(run.sqliteIntegrity ?? "unverified") \
        elapsed=\(String(format: "%.1f", run.elapsedSeconds))s
        decision: \(decision)
        """
        for reason in report.verdict.failureReasons {
            summary += "\n  - \(reason)"
        }
        return summary
    case let .backup(_, name):
        let manifest = try await service.createBackup(name: name)
        return """
        backed up '\(command.profile)' as '\(name)' \
        files=\(manifest.files.count) \
        bytes=\(manifest.files.reduce(0) { $0 + $1.byteCount })
        """
    case let .restore(_, backup):
        let result = try await service.restoreBackup(name: backup, into: service.paths)
        return """
        restored '\(backup)' into '\(command.profile)' \
        files=\(result.restoredFileCount) verified=\(result.verifiedChecksums)
        """
    case let .remove(_, confirmation, exportReport):
        let result = try await service.removeProfile(
            confirmation: confirmation,
            exportReportTo: exportReport.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
        guard result.removedProfile else {
            return "profile '\(command.profile)' was already absent"
        }
        return """
        removed profile '\(command.profile)' \
        exported-reports=\(result.exportedReportCount) residue=\(result.residuePaths.count)
        """
    }
}

struct VerificationFailed: Error, CustomStringConvertible {
    let summary: String
    var description: String { summary }
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try RuntimeCommand.parse(arguments)
    let summary = try await execute(command)
    print(summary)
    exit(RuntimeExitCode.success.rawValue)
} catch let error as RuntimeCommandError {
    writeStandardError("error: \(error.diagnostic)")
    writeStandardError(RuntimeCommand.usage)
    exit(RuntimeExitCode.usage.rawValue)
} catch {
    writeStandardError("error: \(error)")
    exit(RuntimeExitCode(for: error).rawValue)
}
