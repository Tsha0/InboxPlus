// Lets an exploring agent see and drive the Inbox+ window: launch it on the demo inbox, read its
// accessibility tree, press controls, type, scroll and take screenshots.
//
//   swiftc -O Scripts/explore/ui.swift -o build/explore/ui
//
// The process that runs this needs Accessibility access to read and drive the window, and Screen
// Recording access for screenshots; `ui check` reports both. Every command works on the app
// started by `ui launch`, whose process ID is kept in $INBOXPLUS_EXPLORE_DIR/app.pid.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO

let usage = """
usage: ui <command> [arguments]
  check                   report Accessibility, Screen Recording and event-posting access
  launch                  start the app on the demo inbox and wait for its window
  quit                    quit the app
  relaunch                quit and start again, which resets the demo inbox
  crashlog                print the newest crash report for the app, if any
  tree [depth]            list the app's windows, sheets and menus as numbered elements
  press <ref|text>        press an element by its number from `tree`, or by label or identifier
  click <x> <y>           left-click at a screen point
  doubleclick <x> <y>     double-click at a screen point
  rightclick <x> <y>      right-click at a screen point
  type <text>             type text into the focused element ("\\n" presses Return)
  key <combo>             press a key, e.g. return, escape, tab, down, cmd+f, cmd+shift+n
  scroll <x> <y> <lines>  scroll at a screen point: positive scrolls up, negative scrolls down
  resize <width> <height> move the main window to the top left and resize it
  shot <file> [window]    screenshot the screen (or only the main window) to a PNG file
  pause <seconds>         wait, for animations or loading
"""

let environment = ProcessInfo.processInfo.environment
let workDirectory = URL(fileURLWithPath: environment["INBOXPLUS_EXPLORE_DIR"] ?? "build/explore")
let pidFile = workDirectory.appendingPathComponent("app.pid")
let appLog = workDirectory.appendingPathComponent("app.log")

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// MARK: - The app process

func recordedPID() -> pid_t? {
    guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return nil }
    return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

func isRunning(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

/// The running app, or a clear message that it is gone: a vanished app is a finding, not noise.
func runningPID() -> pid_t {
    guard let pid = recordedPID() else { fail("The app has not been launched. Run: ui launch", code: 3) }
    guard isRunning(pid) else {
        fail("The app is not running: it crashed or quit. Run `ui crashlog`, then `ui launch`.", code: 3)
    }
    return pid
}

func onScreenWindows(of pid: pid_t) -> [(id: CGWindowID, frame: CGRect, layer: Int)] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info in
        guard let owner = info[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
              let number = info[kCGWindowNumber as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return (CGWindowID(number), frame, info[kCGWindowLayer as String] as? Int ?? 0)
    }
}

/// The largest ordinary window: the inbox, not a menu or the menu bar item.
func mainWindow(of pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
    onScreenWindows(of: pid)
        .filter { $0.layer == 0 && $0.frame.width > 100 && $0.frame.height > 100 }
        .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        .map { ($0.id, $0.frame) }
}

func launch() {
    guard let path = environment["INBOXPLUS_EXPLORE_APP"] else {
        fail("Set INBOXPLUS_EXPLORE_APP to the InboxPlus executable.")
    }
    if let pid = recordedPID(), isRunning(pid) { fail("The app is already running (pid \(pid)).") }
    try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: appLog.path) {
        FileManager.default.createFile(atPath: appLog.path, contents: nil)
    }
    guard let log = FileHandle(forWritingAtPath: appLog.path) else { fail("Cannot write \(appLog.path)") }
    log.seekToEndOfFile()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    var childEnvironment = environment
    childEnvironment["INBOXPLUS_DEMO"] = "1"
    process.environment = childEnvironment
    process.standardOutput = log
    process.standardError = log
    do { try process.run() } catch { fail("Could not start \(path): \(error)") }
    let pid = process.processIdentifier
    do { try "\(pid)\n".write(to: pidFile, atomically: true, encoding: .utf8) }
    catch { fail("Could not record the process ID: \(error)") }

    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
        // The child is ours until this command exits, so ask the process: a dead child lingers as
        // a zombie that kill(pid, 0) still reports as running.
        guard process.isRunning else { fail("The app exited during launch. See \(appLog.path).", code: 3) }
        if let window = mainWindow(of: pid) {
            print("launched pid \(pid); main window at \(describe(window.frame))")
            return
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    fail("The app started (pid \(pid)) but showed no window within 90 seconds.", code: 3)
}

func quit() {
    guard let pid = recordedPID(), isRunning(pid) else { print("not running"); return }
    NSRunningApplication(processIdentifier: pid)?.terminate()
    let deadline = Date().addingTimeInterval(15)
    while isRunning(pid), Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
    if isRunning(pid) { kill(pid, SIGKILL) }
    print("quit pid \(pid)")
}

func printCrashLog() {
    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")
    let reports = ((try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []).filter { $0.lastPathComponent.hasPrefix("InboxPlus") }
    let newest = reports.max { a, b in
        let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return dateA < dateB
    }
    guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8) else {
        print("No crash report for InboxPlus. The last lines of the app log:")
        let log = (try? String(contentsOf: appLog, encoding: .utf8)) ?? ""
        print(log.split(separator: "\n", omittingEmptySubsequences: false).suffix(40).joined(separator: "\n"))
        return
    }
    print("\(newest.lastPathComponent):")
    print(String(text.prefix(6000)))
}

// MARK: - Accessibility

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
}

func text(_ element: AXUIElement, _ attribute: String) -> String? {
    switch value(element, attribute) {
    case let string as String: return string.isEmpty ? nil : string
    case let number as NSNumber: return number.stringValue
    default: return nil
    }
}

func flag(_ element: AXUIElement, _ attribute: String) -> Bool? {
    (value(element, attribute) as? NSNumber)?.boolValue
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func describe(_ rect: CGRect) -> String {
    "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
}

let identifierAttribute = "AXIdentifier"
let placeholderAttribute = "AXPlaceholderValue"

func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, identifierAttribute, kAXValueAttribute,
     placeholderAttribute, kAXHelpAttribute].compactMap { text(element, $0) }
}

struct Node {
    let element: AXUIElement
    let depth: Int
}

/// Windows, sheets, popovers and open menus first, then the menu bar, so an element's number stays
/// the same whether or not menus are listed.
func walk(pid: pid_t, maxDepth: Int) -> [Node] {
    let app = AXUIElementCreateApplication(pid)
    let roots = children(app)
    let ordered = roots.filter { text($0, kAXRoleAttribute) != kAXMenuBarRole }
        + roots.filter { text($0, kAXRoleAttribute) == kAXMenuBarRole }
    var nodes: [Node] = []
    func visit(_ element: AXUIElement, _ depth: Int) {
        guard nodes.count < 5000 else { return }
        nodes.append(Node(element: element, depth: depth))
        guard depth < maxDepth else { return }
        for child in children(element) { visit(child, depth + 1) }
    }
    for root in ordered { visit(root, 0) }
    return nodes
}

let quietRoles: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXUnknown",
                               "AXSplitter", "AXList", "AXOutline", "AXColumn", "AXCell", "AXRow"]

func line(for node: Node, ref: Int) -> String? {
    let element = node.element
    let role = text(element, kAXRoleAttribute) ?? "?"
    let subrole = text(element, kAXSubroleAttribute)
    let words = labels(element)
    let pressable = actions(element).contains(kAXPressAction)
    if quietRoles.contains(role), words.isEmpty, !pressable { return nil }

    var parts = ["[\(ref)]", role + (subrole.map { "/\($0)" } ?? "")]
    if let title = text(element, kAXTitleAttribute) { parts.append("\"\(clip(title))\"") }
    if let description = text(element, kAXDescriptionAttribute) { parts.append("desc=\"\(clip(description))\"") }
    if let identifier = text(element, identifierAttribute) { parts.append("id=\(identifier)") }
    if let current = text(element, kAXValueAttribute) { parts.append("value=\"\(clip(current))\"") }
    if let placeholder = text(element, placeholderAttribute) { parts.append("placeholder=\"\(clip(placeholder))\"") }
    if let rect = frame(element) { parts.append(describe(rect)) }
    if flag(element, kAXEnabledAttribute) == false { parts.append("disabled") }
    if flag(element, kAXFocusedAttribute) == true { parts.append("focused") }
    if flag(element, kAXSelectedAttribute) == true { parts.append("selected") }
    let extra = actions(element).filter { $0 != kAXPressAction && $0 != "AXScrollToVisible" && $0 != kAXShowMenuAction }
    if pressable { parts.append("pressable") }
    if !extra.isEmpty { parts.append("actions=" + extra.joined(separator: ",")) }
    if role == "AXButton" || role == "AXCheckBox" || role == "AXMenuButton", words.isEmpty {
        parts.append("NO-LABEL")
    }
    return String(repeating: "  ", count: min(node.depth, 14)) + parts.joined(separator: " ")
}

func clip(_ string: String) -> String {
    let flat = string.replacingOccurrences(of: "\n", with: "⏎")
    return flat.count > 120 ? String(flat.prefix(117)) + "…" : flat
}

func resolve(_ query: String, in nodes: [Node]) -> (ref: Int, element: AXUIElement)? {
    if let ref = Int(query) { return nodes.indices.contains(ref) ? (ref, nodes[ref].element) : nil }
    let wanted = query.lowercased()
    let indexed = nodes.enumerated().map { (ref: $0.offset, element: $0.element.element) }
    func best(_ matches: [(ref: Int, element: AXUIElement)]) -> (ref: Int, element: AXUIElement)? {
        matches.first { actions($0.element).contains(kAXPressAction) } ?? matches.first
    }
    let exact = indexed.filter { labels($0.element).contains { $0.lowercased() == wanted } }
    if let match = best(exact) { return match }
    return best(indexed.filter { labels($0.element).contains { $0.lowercased().contains(wanted) } })
}

func bringToFront(_ pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
}

// MARK: - Input

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(20_000)
}

func click(_ point: CGPoint, button: CGMouseButton = .left, count: Int = 1) {
    let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
    let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button))
    usleep(60_000)
    for clickNumber in 1...count {
        for type in [down, up] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            post(event)
        }
        usleep(80_000)
    }
}

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53,
    "esc": 53, "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
    "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "`": 50,
]

func pressKey(_ combo: String) {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    guard let name = parts.last, let code = keyCodes[name] else { fail("Unknown key in \"\(combo)\".") }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        switch modifier {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: fail("Unknown modifier \"\(modifier)\" in \"\(combo)\".")
        }
    }
    for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown)
        event?.flags = flags
        post(event)
    }
}

func typeText(_ string: String) {
    let unescaped = string.replacingOccurrences(of: "\\n", with: "\n")
    for character in unescaped {
        if character == "\n" { pressKey("return"); continue }
        var units = Array(String(character).utf16)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            post(event)
        }
    }
}

// MARK: - Screenshots

func screenshot(to path: String, windowOnly: Bool, pid: pid_t) {
    var arguments = ["-x", "-o"]
    var window: (id: CGWindowID, frame: CGRect)?
    if windowOnly {
        guard let main = mainWindow(of: pid) else { fail("The app has no window on screen.") }
        window = main
        arguments.append("-l\(main.id)")
    }
    arguments.append(path)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = arguments
    do { try process.run() } catch { fail("screencapture did not start: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { fail("The screenshot failed. Check Screen Recording access with `ui check`.") }

    let pointWidth = window?.frame.width ?? (NSScreen.main?.frame.width ?? CGFloat(width))
    let scale = CGFloat(width) / max(pointWidth, 1)
    let origin = window.map { "window at \(describe($0.frame))" } ?? "full screen"
    print("saved \(path): \(width)×\(height) px, \(origin), \(String(format: "%.1f", scale)) px per point")
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let rest = Array(arguments.dropFirst())

func number(_ index: Int) -> Double {
    guard rest.indices.contains(index), let value = Double(rest[index]) else { fail(usage) }
    return value
}

switch command {
case "check":
    let accessibility = AXIsProcessTrusted()
    print("accessibility: \(accessibility ? "granted" : "missing")")
    print("screen recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "missing")")
    print("post events: \(CGPreflightPostEventAccess() ? "granted" : "missing")")
    exit(accessibility ? 0 : 2)
case "launch":
    launch()
case "quit":
    quit()
case "relaunch":
    quit()
    launch()
case "crashlog":
    printCrashLog()
case "tree":
    let pid = runningPID()
    let depth = rest.first.flatMap(Int.init) ?? 40
    let nodes = walk(pid: pid, maxDepth: depth)
    guard !nodes.isEmpty else { fail("No accessibility elements. Check access with `ui check`.") }
    for (ref, node) in nodes.enumerated() { if let row = line(for: node, ref: ref) { print(row) } }
case "press":
    let pid = runningPID()
    guard let query = rest.first else { fail(usage) }
    bringToFront(pid)
    let nodes = walk(pid: pid, maxDepth: 40)
    guard let match = resolve(query, in: nodes) else { fail("No element matches \"\(query)\". Run `ui tree`.") }
    let summary = line(for: nodes[match.ref], ref: match.ref)?.trimmingCharacters(in: .whitespaces) ?? "[\(match.ref)]"
    if actions(match.element).contains(kAXPressAction),
       AXUIElementPerformAction(match.element, kAXPressAction as CFString) == .success {
        print("pressed \(summary)")
    } else if let rect = frame(match.element) {
        click(CGPoint(x: rect.midX, y: rect.midY))
        print("clicked the centre of \(summary)")
    } else {
        fail("\(summary) cannot be pressed and has no position.")
    }
case "click", "doubleclick", "rightclick":
    let pid = runningPID()
    bringToFront(pid)
    let point = CGPoint(x: number(0), y: number(1))
    switch command {
    case "doubleclick": click(point, count: 2)
    case "rightclick": click(point, button: .right)
    default: click(point)
    }
    print("\(command) at (\(Int(point.x)),\(Int(point.y)))")
case "type":
    let pid = runningPID()
    guard !rest.isEmpty else { fail(usage) }
    bringToFront(pid)
    typeText(rest.joined(separator: " "))
    print("typed \(rest.joined(separator: " ").count) characters")
case "key":
    let pid = runningPID()
    guard let combo = rest.first else { fail(usage) }
    bringToFront(pid)
    pressKey(combo)
    print("pressed \(combo)")
case "scroll":
    let pid = runningPID()
    bringToFront(pid)
    let point = CGPoint(x: number(0), y: number(1))
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    usleep(60_000)
    post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                 wheel1: Int32(number(2)), wheel2: 0, wheel3: 0))
    print("scrolled \(Int(number(2))) lines at (\(Int(point.x)),\(Int(point.y)))")
case "resize":
    let pid = runningPID()
    let app = AXUIElementCreateApplication(pid)
    let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let window = windows.max(by: { (frame($0)?.width ?? 0) < (frame($1)?.width ?? 0) }) else {
        fail("The app has no window.")
    }
    var origin = CGPoint(x: 20, y: 40)
    var size = CGSize(width: number(0), height: number(1))
    if let position = AXValueCreate(.cgPoint, &origin) {
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }
    if let extent = AXValueCreate(.cgSize, &size) {
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
    }
    print("window is now \(frame(window).map(describe) ?? "unknown") (the app may enforce a minimum size)")
case "shot":
    let pid = runningPID()
    guard let path = rest.first else { fail(usage) }
    screenshot(to: path, windowOnly: rest.dropFirst().first == "window", pid: pid)
case "pause":
    Thread.sleep(forTimeInterval: min(max(number(0), 0), 30))
    print("waited \(number(0)) s")
default:
    fail(usage)
}
