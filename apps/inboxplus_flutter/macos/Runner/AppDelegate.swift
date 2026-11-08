import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationPending = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let services = InboxPlusAppleServices.shared else { return .terminateCancel }
    if services.canClose { return .terminateNow }
    guard !terminationPending else { return .terminateLater }
    terminationPending = true
    services.prepareToTerminate { [weak self] allowed in
      self?.terminationPending = false
      sender.reply(toApplicationShouldTerminate: allowed)
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    sender.windows.first { $0 is MainFlutterWindow }?.makeKeyAndOrderFront(nil)
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
