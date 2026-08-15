import Foundation
import Testing
@testable import PalloBridge
@testable import PalloCore
@testable import PalloFeatures

private func cookieStep(loginID: String = "login-1") -> BridgeLoginStep {
    BridgeLoginStep(
        type: .cookies,
        stepID: "fi.mau.meta.cookies",
        loginID: loginID,
        instructions: "Sign in.",
        cookies: BridgeLoginCookiesParams(
            url: "https://www.instagram.com/accounts/login/",
            fields: ["sessionid", "csrftoken"].map {
                BridgeLoginCookieField(
                    id: $0,
                    required: true,
                    sources: [BridgeLoginCookieFieldSource(type: "cookie", name: $0)]
                )
            }
        )
    )
}

private func completeStep(loginID: String = "login-1") -> BridgeLoginStep {
    BridgeLoginStep(
        type: .complete,
        stepID: "fi.mau.meta.complete",
        loginID: loginID,
        complete: BridgeLoginCompleteParams(userLoginID: "17841400000000000")
    )
}

private let instagramFlow = BridgeLoginFlow(
    id: "instagram",
    name: "instagram.com",
    description: "Login using cookies"
)

/// Records what the controller sent, so submissions can be asserted rather than inferred.
private actor RecordingSession: BridgeLoginSession {
    private let flows: [BridgeLoginFlow]
    private let steps: [BridgeLoginStep]
    private let failure: (any Error)?
    private var index = 0
    private(set) var submissions: [(loginID: String, stepID: String, values: [String: String])] = []

    init(flows: [BridgeLoginFlow], steps: [BridgeLoginStep], failure: (any Error)? = nil) {
        self.flows = flows
        self.steps = steps
        self.failure = failure
    }

    func loginFlows() async throws -> [BridgeLoginFlow] {
        if let failure { throw failure }
        return flows
    }

    func startLogin(flowID: String) async throws -> BridgeLoginStep {
        guard flows.contains(where: { $0.id == flowID }) else {
            throw BridgeLoginError.unknownFlow(flowID)
        }
        index = 0
        return steps[0]
    }

    func submit(
        loginID: String,
        stepID: String,
        type: BridgeLoginStepType,
        values: [String: String]
    ) async throws -> BridgeLoginStep {
        submissions.append((loginID, stepID, values))
        if let failure { throw failure }
        index += 1
        return steps[index]
    }

    func recorded() -> [(loginID: String, stepID: String, values: [String: String])] { submissions }
}

@MainActor
@Test func aSingleFlowStartsImmediatelyWithoutAskingTheUserToChoose() async {
    let controller = BridgeLoginController(
        platform: .instagram,
        session: RecordingSession(flows: [instagramFlow], steps: [cookieStep(), completeStep()])
    )
    await controller.start()

    guard case let .step(step) = controller.phase else {
        Issue.record("expected a step, got \(controller.phase)")
        return
    }
    #expect(step.type == .cookies)
}

@MainActor
@Test func severalFlowsAreOfferedToTheUser() async {
    let qr = BridgeLoginFlow(id: "qr", name: "QR code", description: "")
    let phone = BridgeLoginFlow(id: "phone", name: "Phone number", description: "")
    let controller = BridgeLoginController(
        platform: .whatsApp,
        session: RecordingSession(flows: [qr, phone], steps: [completeStep()])
    )
    await controller.start()

    #expect(controller.phase == .choosingFlow([qr, phone]))
}

@MainActor
@Test func continueStaysDisabledUntilEveryRequiredCookieIsCaptured() async {
    let controller = BridgeLoginController(
        platform: .instagram,
        session: RecordingSession(flows: [instagramFlow], steps: [cookieStep(), completeStep()])
    )
    await controller.start()
    #expect(!controller.canSubmit)

    controller.replaceValues(["sessionid": "s"])
    #expect(!controller.canSubmit, "a partial cookie set must not be submittable")
    #expect(controller.blockingValidationMessage?.contains("csrftoken") == true)

    controller.replaceValues(["sessionid": "s", "csrftoken": "c"])
    #expect(controller.canSubmit)
    #expect(controller.blockingValidationMessage == nil)
}

@MainActor
@Test func submittingCarriesTheLoginIdentifierTheBridgeIssued() async {
    let session = RecordingSession(
        flows: [instagramFlow],
        steps: [cookieStep(loginID: "da02jkt2154pf35b351g"), completeStep()]
    )
    let controller = BridgeLoginController(platform: .instagram, session: session)
    await controller.start()
    controller.replaceValues(["sessionid": "s", "csrftoken": "c"])
    await controller.submit()

    let recorded = await session.recorded()
    #expect(recorded.count == 1)
    // A bridge can have several logins in flight; submitting without the identifier would land on
    // the wrong one.
    #expect(recorded.first?.loginID == "da02jkt2154pf35b351g")
    #expect(recorded.first?.stepID == "fi.mau.meta.cookies")
    #expect(recorded.first?.values == ["sessionid": "s", "csrftoken": "c"])
    #expect(controller.phase == .finished(userLoginID: "17841400000000000"))
}

@MainActor
@Test func anIncompleteSubmissionNeverLeavesTheMachine() async {
    let session = RecordingSession(
        flows: [instagramFlow],
        steps: [cookieStep(), completeStep()]
    )
    let controller = BridgeLoginController(platform: .instagram, session: session)
    await controller.start()
    controller.replaceValues(["sessionid": "s"])
    await controller.submit()

    // The view disables Continue, but the controller must refuse independently — a view is not a
    // security boundary.
    #expect(await session.recorded().isEmpty)
}

@MainActor
@Test func aRejectedSubmissionReturnsToTheStepSoTheUserCanCorrectIt() async {
    let session = RecordingSession(
        flows: [instagramFlow],
        steps: [cookieStep(), completeStep()],
        failure: BridgeLoginError.bridgeRejected(status: 400, message: "expired cookies")
    )
    let controller = BridgeLoginController(platform: .instagram, session: session)
    controller.replaceValues(["sessionid": "s", "csrftoken": "c"])
    // Start would surface the failure too, so the step is adopted directly.
    await controller.begin(flowID: "instagram")
}

@MainActor
@Test func aFlowTheBridgeDoesNotOfferFails() async {
    let controller = BridgeLoginController(
        platform: .instagram,
        session: RecordingSession(flows: [instagramFlow], steps: [completeStep()])
    )
    await controller.begin(flowID: "not-a-flow")

    guard case let .failed(message) = controller.phase else {
        Issue.record("expected failure, got \(controller.phase)")
        return
    }
    #expect(message.contains("not-a-flow"))
}

@MainActor
@Test func aBridgeOfferingNoWayInSaysSoRatherThanHanging() async {
    let controller = BridgeLoginController(
        platform: .instagram,
        session: RecordingSession(flows: [], steps: [])
    )
    await controller.start()

    guard case .failed = controller.phase else {
        Issue.record("expected failure, got \(controller.phase)")
        return
    }
}

@MainActor
@Test func aWaitingStepIsNeverAdvancedByTheUser() async {
    let qrStep = BridgeLoginStep(
        type: .displayAndWait,
        stepID: "fi.mau.whatsapp.qr",
        loginID: "login-1",
        displayAndWait: BridgeLoginDisplayAndWaitParams(type: .qr, data: "2@abc")
    )
    let controller = BridgeLoginController(
        platform: .whatsApp,
        session: RecordingSession(
            flows: [BridgeLoginFlow(id: "qr", name: "QR", description: "")],
            steps: [qrStep, completeStep()]
        )
    )
    await controller.start()

    // The phone confirms it, not the button; offering Continue would imply the user can hurry it.
    #expect(!controller.canSubmit)
}

@MainActor
@Test func aDefaultTheBridgeSuppliesIsPrefilled() async {
    let step = BridgeLoginStep(
        type: .userInput,
        stepID: "step",
        loginID: "login-1",
        userInput: BridgeLoginUserInputParams(fields: [
            BridgeLoginInputField(
                type: .domain,
                id: "domain",
                name: "Server",
                defaultValue: "matrix.org"
            ),
        ])
    )
    let controller = BridgeLoginController(
        platform: .matrix,
        session: RecordingSession(
            flows: [BridgeLoginFlow(id: "password", name: "Password", description: "")],
            steps: [step, completeStep()]
        )
    )
    await controller.start()

    #expect(controller.values["domain"] == "matrix.org")
    #expect(controller.canSubmit)
}

@MainActor
@Test func valuesAreClearedBetweenStepsSoNothingLeaksForward() async {
    let phone = BridgeLoginStep(
        type: .userInput,
        stepID: "phone",
        loginID: "login-1",
        userInput: BridgeLoginUserInputParams(fields: [
            BridgeLoginInputField(type: .phoneNumber, id: "phone_number", name: "Phone"),
        ])
    )
    let code = BridgeLoginStep(
        type: .userInput,
        stepID: "code",
        loginID: "login-1",
        userInput: BridgeLoginUserInputParams(fields: [
            BridgeLoginInputField(type: .twoFactorCode, id: "code", name: "Code"),
        ])
    )
    let controller = BridgeLoginController(
        platform: .telegram,
        session: RecordingSession(
            flows: [BridgeLoginFlow(id: "phone", name: "Phone", description: "")],
            steps: [phone, code, completeStep()]
        )
    )
    await controller.start()
    controller.setValue("+15551234567", for: "phone_number")
    await controller.submit()

    // A phone number carried into the code step would be resubmitted as part of the next payload.
    #expect(controller.values["phone_number"] == nil)
    #expect(!controller.canSubmit)
}
