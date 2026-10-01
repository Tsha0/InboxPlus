import Foundation
import InboxPlusBridgeService
import InboxPlusRuntime

// Build-time helper only; it is never copied into the app bundle.
@main struct RuntimeBundler {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else { fatalError("usage: InboxPlusRuntimeBundler libolm|bootstrap <directory>") }
        let directory = URL(fileURLWithPath: arguments[1])
        if arguments[0] == "libolm" {
            _ = try await LibolmProvisioner(bundledLibrary: nil).install(into: directory)
        } else if arguments[0] == "bootstrap" {
            let service = RuntimeProfileService(
                paths: try RuntimePaths(root: directory, profileName: "default"),
                packageRoot: RuntimeProfileService.resolvedPackageRoot()
            )
            let lock = try service.acquireProfileLock()
            defer { withExtendedLifetime(lock) {} }
            _ = try service.bootstrapBundled()
        } else { fatalError("unknown bundler command") }
    }
}
