import Foundation

/// This module's bundled images.
///
/// Don't use SwiftPM's generated `Bundle.module` here. It only looks beside `Inbox+.app` and in the
/// absolute `.build` path of the Mac that compiled it, and traps when neither exists, which in a
/// shipped app is every Mac but the build machine (#117). The app scripts install the bundle in
/// `Contents/Resources`, because the app's root can't hold unsealed files.
enum UIResources {
    static let bundleName = "InboxPlus_InboxPlusUI.bundle"

    static let bundle: Bundle? = bundle(in: .main)

    /// `Contents/Resources` in the app; beside the executable for `swift run`. Nil rather than a
    /// crash when it is missing, so callers fall back to a system image.
    static func bundle(in main: Bundle) -> Bundle? {
        [main.resourceURL, main.bundleURL]
            .compactMap { $0?.appendingPathComponent(bundleName, isDirectory: true) }
            .lazy
            .compactMap(Bundle.init(url:))
            .first
    }
}
