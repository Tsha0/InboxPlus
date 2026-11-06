import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var services: InboxPlusAppleServices?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 900, height: 600)
    self.setContentSize(NSSize(width: 1100, height: 700))

    RegisterGeneratedPlugins(registry: flutterViewController)
    services = InboxPlusAppleServices(messenger: flutterViewController.engine.binaryMessenger)
    delegate = self

    super.awakeFromNib()
  }
}

extension MainFlutterWindow: NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let services else { return false }
    services.prepareToHide(sender)
    return false
  }
}
