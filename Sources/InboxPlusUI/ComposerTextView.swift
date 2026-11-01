import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Something pasted or dropped that becomes a staged attachment rather than text.
enum StageableContent: Equatable {
    case files([URL])
    /// A picture with no file behind it, such as a screenshot copied to the clipboard.
    case image(Data, filename: String)

    static let imageName = "Image"

    /// Files come first: Finder puts a copied file's name and icon on the pasteboard beside the
    /// file itself. Text comes next: Word and Pages put a picture of copied text beside the text.
    static func read(from pasteboard: NSPasteboard) -> StageableContent? {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLsOnly) as? [URL] ?? []
        if !files.isEmpty { return .files(files) }
        guard pasteboard.availableType(from: [.string]) == nil,
              let type = imageType(on: pasteboard),
              let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier))
        else { return nil }
        return image(data, type: type)
    }

    /// The same decision as `read(from:)`, without converting any picture.
    static func isOffered(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLsOnly)
            || (pasteboard.availableType(from: [.string]) == nil && imageType(on: pasteboard) != nil)
    }

    /// Formats every network takes are kept as they are; re-encoding a GIF would stop it moving.
    /// Anything else, like the TIFF most apps copy, becomes a PNG.
    static func image(_ data: Data, type: UTType) -> StageableContent? {
        if let kept = [UTType.png, .jpeg, .gif].first(where: { type.conforms(to: $0) }),
           let fileExtension = kept.preferredFilenameExtension {
            return .image(data, filename: "\(imageName).\(fileExtension)")
        }
        guard let tiff = NSImage(data: data)?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return .image(png, filename: "\(imageName).png")
    }

    /// Reads one item dragged onto the conversation.
    @MainActor
    static func load(from provider: NSItemProvider) async -> StageableContent? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            return url.map { .files([$0]) }
        }
        guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else { return nil }
        let data = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
        return data.flatMap { image($0, type: type) }
    }

    private static var fileURLsOnly: [NSPasteboard.ReadingOptionKey: Any] { [.urlReadingFileURLsOnly: true] }

    private static func imageType(on pasteboard: NSPasteboard) -> UTType? {
        pasteboard.types?.lazy
            .compactMap { UTType($0.rawValue) }
            .first { $0.conforms(to: .image) }
    }
}

/// The composer's text view: Return sends, Shift-Return starts a new line, and a pasted or dropped
/// file or picture is staged instead of being inserted as text.
final class ComposerTextView: NSTextView {
    static let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let maximumVisibleLines = 6

    var onSubmit: () -> Void = {}
    /// Nil where the conversation takes no attachments; a paste or drop is then ordinary text.
    var onStage: ((StageableContent) -> Void)?
    var onCancel: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        returnPressed(modifiers: NSApp?.currentEvent?.modifierFlags ?? [])
    }

    /// Option-Return inserts a new line too, through `insertNewlineIgnoringFieldEditor`, as it
    /// does in any Mac text field.
    func returnPressed(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            super.insertNewline(nil)
        } else {
            onSubmit()
        }
    }

    /// Tab moves on, as it did when the composer was a text field; Option-Tab still types one.
    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(sender)
    }

    /// Escape, which a text view would otherwise turn into a completion list.
    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }

    override func paste(_ sender: Any?) {
        if !stage(from: .general) { super.paste(sender) }
    }

    /// Hands a file or picture over to be staged. Returns false for anything that is text.
    func stage(from pasteboard: NSPasteboard) -> Bool {
        guard let onStage, let content = StageableContent.read(from: pasteboard) else { return false }
        onStage(content)
        return true
    }

    func stages(_ pasteboard: NSPasteboard) -> Bool {
        onStage != nil && StageableContent.isOffered(on: pasteboard)
    }

    /// A plain-text view disables Paste for a pasteboard holding only a picture.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)), stages(.general) { return true }
        return super.validateMenuItem(menuItem)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        stages(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        stages(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        stage(from: sender.draggingPasteboard) || super.performDragOperation(sender)
    }

    /// Opening a conversation means writing in it. Deferred a turn, because SwiftUI settles its own
    /// focus as the view appears and would otherwise take it straight back.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    /// One line when empty, growing with the text up to `maximumVisibleLines`, then scrolling.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.textFont]
        func height(of text: String) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height)
        }
        // A trailing new line already holds the caret on a line of its own, but measures as nothing.
        let content = height(of: string.isEmpty || string.hasSuffix("\n") ? string + " " : string)
        let line = height(of: " ")
        return min(max(content, line), line * CGFloat(Self.maximumVisibleLines))
    }
}

struct ComposerTextEditor: NSViewRepresentable {
    let text: String
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void
    let onStage: ((StageableContent) -> Void)?
    var onCancel: (() -> Void)?
    /// Changing it puts the cursor in the composer, as choosing Reply does.
    var focusRequest = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, focusRequest: focusRequest)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = context.coordinator.textView
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = ComposerTextView.textFont
        textView.textColor = .textColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Message")
        textView.setAccessibilityPlaceholderValue("Message…")
        textView.setAccessibilityIdentifier("message-composer")

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        context.coordinator.onTextChange = onTextChange
        textView.onSubmit = onSubmit
        textView.onStage = onStage
        textView.onCancel = onCancel
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }
        // Never while an input method is composing: the half-typed characters are not in the
        // draft yet, and replacing the text would throw them away.
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            // Earlier typing cannot be undone into text that has been replaced underneath it.
            context.coordinator.undoManager.removeAllActions()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: width, height: context.coordinator.textView.fittingHeight(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let textView = ComposerTextView()
        let undoManager = UndoManager()
        var onTextChange: (String) -> Void
        var focusRequest: Int

        init(onTextChange: @escaping (String) -> Void, focusRequest: Int) {
            self.onTextChange = onTextChange
            self.focusRequest = focusRequest
        }

        func textDidChange(_ notification: Notification) {
            onTextChange(textView.string)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
    }
}
