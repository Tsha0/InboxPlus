import Foundation
import PalloRuntime

public struct BenchmarkCLIOptions: Equatable, Sendable {
    public static let defaultSeed: UInt64 = 20_260_813
    public static let defaultRooms = 2_000
    public static let defaultMessages = 100_000
    public static let defaultImportWorkers = 3

    public let seed: UInt64
    public let rooms: Int
    public let messages: Int
    public let importWorkers: Int

    public init(seed: UInt64, rooms: Int, messages: Int, importWorkers: Int) {
        self.seed = seed
        self.rooms = rooms
        self.messages = messages
        self.importWorkers = importWorkers
    }
}

public struct VerifyCLIOptions: Equatable, Sendable {
    public let fixtureRooms: Int?
    public let simulateDataLoss: Bool
    public let restoreBackup: String?
    public let reportName: String?

    public init(
        fixtureRooms: Int?,
        simulateDataLoss: Bool,
        restoreBackup: String?,
        reportName: String?
    ) {
        self.fixtureRooms = fixtureRooms
        self.simulateDataLoss = simulateDataLoss
        self.restoreBackup = restoreBackup
        self.reportName = reportName
    }
}

public enum RuntimeCommand: Equatable, Sendable {
    case bootstrap(profile: String, python: String)
    case start(profile: String)
    case status(profile: String)
    case stop(profile: String)
    case benchmark(profile: String, options: BenchmarkCLIOptions)
    case backup(profile: String, name: String)
    case restore(profile: String, backup: String)
    case verify(profile: String, options: VerifyCLIOptions)
    case remove(profile: String, confirmation: String, exportReport: String?)

    public var profile: String {
        switch self {
        case let .bootstrap(profile, _),
             let .start(profile),
             let .status(profile),
             let .stop(profile),
             let .benchmark(profile, _),
             let .backup(profile, _),
             let .restore(profile, _),
             let .verify(profile, _),
             let .remove(profile, _, _):
            profile
        }
    }

    /// True when the command only reads runtime state and must not take the exclusive profile lock.
    public var observesOnly: Bool {
        if case .status = self { return true }
        return false
    }

    public static let usage = """
    Usage: PalloRuntimeCLI <command> [options]

    Commands:
      bootstrap --profile <name> --python <path>
          Prepare the pinned profile-local Synapse runtime.
      start --profile <name>
          Launch the supervised loopback-only Synapse process.
      status --profile <name>
          Report the persisted lifecycle phase and health.
      stop --profile <name>
          Gracefully stop the supervised process and verify the listener is gone.
      benchmark --profile <name> [--seed <n>] [--rooms <n>] [--messages <n>] [--import-workers <n>]
          Run the representative concurrent workload and write a redacted report.
      backup --profile <name> --name <backup>
          Create an offline, checksummed backup of a stopped profile.
      restore --profile <name> --backup <backup>
          Restore a verified backup into an empty profile.
      verify --profile <name> [--fixture-rooms <n>] [--simulate-data-loss] [--restore <backup>] [--report <name>]
          Verify the prepared runtime, fixtures, reports, or destructive recovery.
      remove --profile <name> --confirm <name> [--export-report <path>]
          Stop and remove exactly one contained profile after confirmation.
    """

    public static func parse(_ arguments: [String]) throws -> RuntimeCommand {
        guard let name = arguments.first else { throw RuntimeCommandError.missingCommand }
        let tokens = Array(arguments.dropFirst())

        switch name {
        case "bootstrap":
            let options = try Options(tokens, valued: ["--profile", "--python"], flags: [])
            return .bootstrap(
                profile: try options.require("--profile"),
                python: try options.require("--python")
            )
        case "start":
            let options = try Options(tokens, valued: ["--profile"], flags: [])
            return .start(profile: try options.require("--profile"))
        case "status":
            let options = try Options(tokens, valued: ["--profile"], flags: [])
            return .status(profile: try options.require("--profile"))
        case "stop":
            let options = try Options(tokens, valued: ["--profile"], flags: [])
            return .stop(profile: try options.require("--profile"))
        case "benchmark":
            let options = try Options(
                tokens,
                valued: ["--profile", "--seed", "--rooms", "--messages", "--import-workers"],
                flags: []
            )
            return .benchmark(
                profile: try options.require("--profile"),
                options: BenchmarkCLIOptions(
                    seed: try options.unsignedInteger("--seed", default: BenchmarkCLIOptions.defaultSeed),
                    rooms: try options.positiveInteger("--rooms", default: BenchmarkCLIOptions.defaultRooms),
                    messages: try options.positiveInteger(
                        "--messages",
                        default: BenchmarkCLIOptions.defaultMessages
                    ),
                    importWorkers: try options.positiveInteger(
                        "--import-workers",
                        default: BenchmarkCLIOptions.defaultImportWorkers
                    )
                )
            )
        case "backup":
            let options = try Options(tokens, valued: ["--profile", "--name"], flags: [])
            return .backup(
                profile: try options.require("--profile"),
                name: try options.require("--name")
            )
        case "restore":
            let options = try Options(tokens, valued: ["--profile", "--backup"], flags: [])
            return .restore(
                profile: try options.require("--profile"),
                backup: try options.require("--backup")
            )
        case "verify":
            let options = try Options(
                tokens,
                valued: ["--profile", "--fixture-rooms", "--restore", "--report"],
                flags: ["--simulate-data-loss"]
            )
            return .verify(
                profile: try options.require("--profile"),
                options: VerifyCLIOptions(
                    fixtureRooms: try options.optionalPositiveInteger("--fixture-rooms"),
                    simulateDataLoss: options.flag("--simulate-data-loss"),
                    restoreBackup: options.value("--restore"),
                    reportName: options.value("--report")
                )
            )
        case "remove":
            let options = try Options(
                tokens,
                valued: ["--profile", "--confirm", "--export-report"],
                flags: []
            )
            return .remove(
                profile: try options.require("--profile"),
                confirmation: try options.require("--confirm"),
                exportReport: options.value("--export-report")
            )
        default:
            throw RuntimeCommandError.unknownCommand(name)
        }
    }
}

private struct Options {
    private var values: [String: String] = [:]
    private var presentFlags: Set<String> = []

    init(_ tokens: [String], valued: Set<String>, flags: Set<String>) throws {
        var seen: Set<String> = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.hasPrefix("--") else {
                throw RuntimeCommandError.unexpectedArgument(token)
            }
            if flags.contains(token) {
                guard seen.insert(token).inserted else {
                    throw RuntimeCommandError.duplicateOption(token)
                }
                presentFlags.insert(token)
                index += 1
                continue
            }
            guard valued.contains(token) else {
                throw RuntimeCommandError.unknownOption(token)
            }
            guard seen.insert(token).inserted else {
                throw RuntimeCommandError.duplicateOption(token)
            }
            guard index + 1 < tokens.count else {
                throw RuntimeCommandError.missingValue(token)
            }
            let value = tokens[index + 1]
            guard !value.hasPrefix("--") else {
                throw RuntimeCommandError.missingValue(token)
            }
            values[token] = value
            index += 2
        }
    }

    func value(_ option: String) -> String? { values[option] }

    func flag(_ option: String) -> Bool { presentFlags.contains(option) }

    func require(_ option: String) throws -> String {
        guard let value = values[option] else {
            throw RuntimeCommandError.missingOption(option)
        }
        return value
    }

    func positiveInteger(_ option: String, default fallback: Int) throws -> Int {
        guard let raw = values[option] else { return fallback }
        guard let parsed = Int(raw), parsed > 0 else {
            throw RuntimeCommandError.invalidValue(option: option, value: raw)
        }
        return parsed
    }

    func optionalPositiveInteger(_ option: String) throws -> Int? {
        guard let raw = values[option] else { return nil }
        guard let parsed = Int(raw), parsed > 0 else {
            throw RuntimeCommandError.invalidValue(option: option, value: raw)
        }
        return parsed
    }

    func unsignedInteger(_ option: String, default fallback: UInt64) throws -> UInt64 {
        guard let raw = values[option] else { return fallback }
        guard let parsed = UInt64(raw) else {
            throw RuntimeCommandError.invalidValue(option: option, value: raw)
        }
        return parsed
    }
}

public enum RuntimeCommandError: Error, Equatable, Sendable {
    case missingCommand
    case unknownCommand(String)
    case missingOption(String)
    case missingValue(String)
    case unknownOption(String)
    case duplicateOption(String)
    case invalidValue(option: String, value: String)
    case unexpectedArgument(String)

    public var diagnostic: String {
        switch self {
        case .missingCommand:
            "no command given"
        case let .unknownCommand(name):
            "unknown command '\(name)'"
        case let .missingOption(option):
            "missing required option \(option)"
        case let .missingValue(option):
            "option \(option) requires a value"
        case let .unknownOption(option):
            "unknown option \(option)"
        case let .duplicateOption(option):
            "option \(option) was given more than once"
        case let .invalidValue(option, value):
            "option \(option) rejected the value '\(value)'"
        case let .unexpectedArgument(argument):
            "unexpected argument '\(argument)'"
        }
    }
}
