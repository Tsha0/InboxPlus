import PalloBridge
import SwiftUI

/// Shown when a bridge offers more than one way in — WhatsApp's QR versus phone number, or
/// Facebook's several sign-in domains.
struct LoginFlowPickerView: View {
    let flows: [BridgeLoginFlow]
    let onSelect: (BridgeLoginFlow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose how to sign in")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(flows, id: \.id) { flow in
                Button { onSelect(flow) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flow.name).fontWeight(.semibold)
                            if !flow.description.isEmpty {
                                Text(flow.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login-flow-\(flow.id)")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

/// Renders a QR payload without pulling in a dependency; CoreImage ships the generator.
enum QRCodeRenderer {
    static func image(for payload: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Scale before rasterising: the generator emits roughly one pixel per module, which is
        // unscannable on screen.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
