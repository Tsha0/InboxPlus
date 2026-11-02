import AppKit
import SwiftUI

struct ImagePreview: View {
    let image: NSImage
    let url: URL
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat?
    @State private var saveFailed = false

    private var imageSize: CGSize {
        let representation = image.representations.max { $0.pixelsWide < $1.pixelsWide }
        return CGSize(
            width: representation?.pixelsWide ?? Int(image.size.width),
            height: representation?.pixelsHigh ?? Int(image.size.height)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 57))
            let scale = zoom ?? Self.fitScale(image: imageSize, viewport: viewport)
            VStack(spacing: 0) {
                HStack {
                    Button("Save As…", action: save)
                    Spacer()
                    Button { zoom = max(0.01, scale / 1.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom out")
                    .disabled(scale <= 0.01)
                    .keyboardShortcut("-", modifiers: .command)
                    Text(scale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: 45)
                    Button { zoom = min(8, scale * 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom in")
                    .disabled(scale >= 8)
                    .keyboardShortcut("+", modifiers: .command)
                    Button("Fit") { zoom = nil }
                    Button("Actual Size") { zoom = 1 }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                        .accessibilityLabel("Image preview")
                        .frame(minWidth: viewport.width, minHeight: viewport.height)
                }
                .background(.quaternary.opacity(0.3))
            }
        }
        .frame(width: 800, height: 600)
        .alert("Image could not be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that the destination is writable and try again.")
        }
    }

    static func fitScale(image: CGSize, viewport: CGSize) -> CGFloat {
        min(1, viewport.width / image.width, viewport.height / image.height)
    }

    static func saveOriginal(from source: URL, to destination: URL) throws {
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.nameFieldStringValue = (filename as NSString).lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try Self.saveOriginal(from: url, to: destination) }
        catch { saveFailed = true }
    }
}
