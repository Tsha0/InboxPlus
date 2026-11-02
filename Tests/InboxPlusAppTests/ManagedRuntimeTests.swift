import Foundation
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

@Test func aServingHomeserverIsUnsupervisedOnlyWhileNoSessionHoldsItsProfile() throws {
    // Break caught: a homeserver whose session had died was attached to on every launch, so the
    // bridges that session ran were never started again.
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches/InboxPlusManagedRuntime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "default")
    let service = RuntimeProfileService(paths: paths, packageRoot: root)

    try withExtendedLifetime(try service.acquireProfileLock()) {
        #expect(!ManagedRuntime.isUnsupervised(paths: paths))
    }
    #expect(ManagedRuntime.isUnsupervised(paths: paths))
    // Asking must not keep the profile from the session launched next.
    #expect(throws: Never.self) { _ = try service.acquireProfileLock() }
}
