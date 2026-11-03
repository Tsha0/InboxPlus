import Foundation
import Testing
@testable import InboxPlusRuntime

@Test func secondProfileLockIsRejected() throws {
    // Break caught: two runtime owners can mutate or supervise the same profile concurrently.
    let directory = lockTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockURL = directory.appendingPathComponent("profile.lock")

    let first = try ProfileLock.acquire(at: lockURL)
    #expect(throws: ProfileLockError.alreadyLocked) {
        try ProfileLock.acquire(at: lockURL)
    }
    withExtendedLifetime(first) {}
}

@Test func releasingProfileLockClosesTheDescriptorAndAllowsReacquisition() throws {
    // Break caught: releasing the owning object leaks the descriptor and permanently wedges the profile.
    let directory = lockTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockURL = directory.appendingPathComponent("profile.lock")

    do {
        let first = try ProfileLock.acquire(at: lockURL)
        withExtendedLifetime(first) {}
    }
    let second = try ProfileLock.acquire(at: lockURL)

    #expect(try lockPermissions(of: lockURL) == 0o600)
    withExtendedLifetime(second) {}
}

@Test func observingProfileOwnershipDoesNotCreateOrRetainALock() throws {
    let directory = lockTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockURL = directory.appendingPathComponent("profile.lock")

    #expect(try !ProfileLock.isHeld(at: lockURL))
    #expect(!FileManager.default.fileExists(atPath: lockURL.path))
    do {
        let owner = try ProfileLock.acquire(at: lockURL)
        #expect(try ProfileLock.isHeld(at: lockURL))
        withExtendedLifetime(owner) {}
    }
    #expect(try !ProfileLock.isHeld(at: lockURL))
    let nextOwner = try ProfileLock.acquire(at: lockURL)
    withExtendedLifetime(nextOwner) {}
}

@Test func observingProfileOwnershipRejectsSymlinks() throws {
    let directory = lockTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockURL = directory.appendingPathComponent("profile.lock")
    try FileManager.default.createSymbolicLink(atPath: lockURL.path, withDestinationPath: "/dev/null")

    #expect(throws: ProfileLockError.self) {
        try ProfileLock.isHeld(at: lockURL)
    }
}

private func lockTestDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".build/ProfileLockTests-\(UUID().uuidString)", isDirectory: true)
}

private func lockPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
