import PalloBridge
import PalloCore
import PalloFeatures
import SwiftUI

/// Renders whatever the bridge asks for next.
///
/// One view per step type, chosen by the protocol rather than by network. Adding a network is
/// catalog data; it is never a new screen.
public struct LoginStepView: View {
    @Bindable private var controller: BridgeLoginController
    private let onFinished: (String) -> Void
    private let onCancel: () -> Void

    public init(
        controller: BridgeLoginController,
        onFinished: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.controller = controller
        self.onFinished = onFinished
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let failure = controller.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .accessibilityIdentifier("login-failure")
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(.background)
        .task { await controller.start() }
        .accessibilityIdentifier("login-flow")
    }

    private var header: some View {
        HStack(spacing: 10) {
            PlatformBadge(platform: controller.platform)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(controller.platform.accessibilityLabel)")
                    .font(.headline)
                if let instructions = controller.currentStep?.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if controller.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .loadingFlows:
            ProgressView("Asking the bridge how to sign in…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .choosingFlow(flows):
            LoginFlowPickerView(flows: flows) { flow in
                Task { await controller.begin(flowID: flow.id) }
            }

        case let .step(step), let .submitting(step):
            stepContent(step)

        case .finished:
            ContentUnavailableView(
                "\(controller.platform.accessibilityLabel) is connected",
                systemImage: "checkmark.circle.fill",
                description: Text("Your conversations will appear in the inbox as they sync.")
            )
            .accessibilityIdentifier("login-complete")

        case let .failed(message):
            ContentUnavailableView(
                "Could not sign in",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .accessibilityIdentifier("login-failed")
        }
    }

    @ViewBuilder private func stepContent(_ step: BridgeLoginStep) -> some View {
        switch step.type {
        case .userInput:
            UserInputStepView(step: step, controller: controller)

        case .cookies:
            if let parameters = step.cookies {
                CookieLoginWebView(parameters: parameters) { captured in
                    controller.replaceValues(captured)
                }
                .accessibilityIdentifier("login-cookies-webview")
            } else {
                unsupported("This bridge asked for cookies but did not say which.")
            }

        case .displayAndWait:
            DisplayAndWaitStepView(parameters: step.displayAndWait)

        case .clientHTTP, .webAuthn:
            // Modelled so the step decodes and the user is told plainly, rather than the login
            // silently stalling on a screen Pallo cannot draw.
            unsupported(
                """
                \(controller.platform.accessibilityLabel) is asking for a sign-in method Pallo \
                does not support yet.
                """
            )

        case .complete:
            EmptyView()
        }
    }

    private func unsupported(_ message: String) -> some View {
        ContentUnavailableView(
            "Unsupported sign-in step",
            systemImage: "questionmark.circle",
            description: Text(message)
        )
    }

    private var footer: some View {
        HStack {
            if let message = controller.blockingValidationMessage,
               controller.currentStep?.type == .cookies {
                Label(message, systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            if case let .finished(userLoginID) = controller.phase {
                Button("Done") { onFinished(userLoginID) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") { Task { await controller.submit() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canSubmit)
                    .accessibilityIdentifier("login-continue")
            }
        }
        .padding(16)
    }
}

/// A typed form for a `user_input` step.
struct UserInputStepView: View {
    let step: BridgeLoginStep
    @Bindable var controller: BridgeLoginController

    var body: some View {
        Form {
            ForEach(step.userInput?.fields ?? [], id: \.id) { field in
                VStack(alignment: .leading, spacing: 4) {
                    field.editor(
                        value: Binding(
                            get: { controller.values[field.id] ?? "" },
                            set: { controller.setValue($0, for: field.id) }
                        )
                    )
                    if !field.description.isEmpty {
                        Text(field.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private extension BridgeLoginInputField {
    /// Secret fields get a `SecureField` so the value is never drawn on screen.
    @ViewBuilder
    func editor(value: Binding<String>) -> some View {
        if type.isSecret {
            SecureField(name, text: value)
                .textContentType(type == .password ? .password : .oneTimeCode)
                .accessibilityIdentifier("login-field-\(id)")
        } else {
            TextField(name, text: value)
                .accessibilityIdentifier("login-field-\(id)")
        }
    }
}

/// A `display_and_wait` step: show the code, wait for the bridge to say it was accepted.
struct DisplayAndWaitStepView: View {
    let parameters: BridgeLoginDisplayAndWaitParams?

    var body: some View {
        VStack(spacing: 16) {
            switch parameters?.type {
            case .qr:
                if let data = parameters?.data, let image = QRCodeRenderer.image(for: data) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .accessibilityLabel("QR code to scan")
                        .accessibilityIdentifier("login-qr")
                } else {
                    ProgressView()
                }
            case .emoji, .code:
                Text(parameters?.data ?? "")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("login-code")
            case .nothing, .none:
                ProgressView()
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to confirm on your phone…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
