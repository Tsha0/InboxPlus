import AppKit
import Foundation
import Testing
@testable import InboxPlusUI

/// A minimal `Inbox+.app` in a fresh temporary directory, laid out the way the build scripts
/// assemble it, optionally with this module's resource bundle in `Contents/Resources`.
private func makeApp(withResources: Bool) throws -> URL {
    let app = FileManager.default.temporaryDirectory
        .appendingPathComponent("UIResourcesTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Inbox+.app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleIdentifier": "com.inboxplus.tests.\(UUID().uuidString)",
        "CFBundleExecutable": "InboxPlus",
        "CFBundlePackageType": "APPL",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    if withResources {
        let bundle = resources.appendingPathComponent(UIResources.bundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let logo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InboxPlusUI/Resources/InboxPlusLogo.png")
        try FileManager.default.copyItem(at: logo, to: bundle.appendingPathComponent("InboxPlusLogo.png"))
    }
    return app
}

@Test func theLogoLoadsFromWhereTheAppBundleInstallsIt() throws {
    // SwiftPM's `Bundle.module` never looks in Contents/Resources, so 0.6.0 crashed on launch on
    // every Mac except the one that built it (#117).
    let app = try makeApp(withResources: true)
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
    let main = try #require(Bundle(url: app))

    let bundle = try #require(UIResources.bundle(in: main))
    #expect(bundle.bundleURL.resolvingSymlinksInPath().path == app
        .appendingPathComponent("Contents/Resources/\(UIResources.bundleName)")
        .resolvingSymlinksInPath().path)
    #expect(bundle.image(forResource: "InboxPlusLogo") != nil)
}

@Test func aMissingResourceBundleIsNilRatherThanACrash() throws {
    let app = try makeApp(withResources: false)
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
    let main = try #require(Bundle(url: app))

    #expect(UIResources.bundle(in: main) == nil)
}

@Test func noSourceUsesTheGeneratedModuleBundle() throws {
    // It traps in a shipped app; `UIResources` is the lookup that works there.
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources", isDirectory: true)
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let file as URL in files where file.pathExtension == "swift" {
        let code = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        if code.contains(where: { $0.contains("Bundle.module") }) {
            offenders.append(file.lastPathComponent)
        }
    }
    #expect(offenders.isEmpty, "Bundle.module is used in \(offenders)")
}
