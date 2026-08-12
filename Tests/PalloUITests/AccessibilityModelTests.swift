import Testing
@testable import PalloCore
@testable import PalloFeatures
@testable import PalloUI

@Test func platformBadgeDescriptorAlwaysNamesTheNetwork() {
    for platform in Platform.allCases {
        let descriptor = PlatformBadgeDescriptor(platform: platform)
        #expect(descriptor.accessibilityLabel == platform.accessibilityLabel)
        #expect(!descriptor.symbolName.isEmpty)
    }
}

@Test func linkedContactCardDescriptorRetainsExactRoute() {
    let route = ConversationRoute(accountID: "wa", conversationID: "chat")
    let descriptor = ContactConversationCardDescriptor(
        route: route,
        platform: .whatsApp,
        title: "Latest message",
        preview: "Hello"
    )
    #expect(descriptor.route == route)
    #expect(descriptor.accessibilityLabel.contains("WhatsApp"))
}
