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
    case .benchmark, .backup, .restore, .remove:
        throw CommandUnavailable(command: command)
    }
}

struct CommandUnavailable: Error {
    let command: RuntimeCommand
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
} catch let error as CommandUnavailable {
    writeStandardError(
        "error: command is recognized but its service is not wired into this build yet"
    )
    _ = error
    exit(30)
} catch {
    writeStandardError("error: \(error)")
    exit(RuntimeExitCode(for: error).rawValue)
}
