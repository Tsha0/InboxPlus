# Pallo Native Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable native macOS Pallo prototype that proves the approved three-pane inbox, manual identity linking, contact-summary navigation, exact-network reply routing, background/menu-bar state, and accessibility using a deterministic in-memory messaging gateway.

**Architecture:** A Swift package contains a SwiftUI executable plus focused domain, gateway, application-state, and feature modules. The UI depends on a `MessagingGateway` protocol rather than Matrix or bridge code; an actor-backed in-memory implementation supplies deterministic conversations and events. This vertical slice fixes product behavior and module boundaries before Synapse, Matrix Rust SDK, and real bridge processes are introduced in later plans.

**Tech Stack:** Swift 6.3, SwiftUI, Observation, Foundation, Swift Testing, Swift Package Manager, macOS 15+, Apple silicon.

## Global Constraints

- The release baseline is Apple silicon running macOS 15 or later; Intel is outside Pallo 1.0.
- The main experience is the approved compact three-pane layout with Pallo navigation rail, unified inbox, and detail pane.
- Network identity uses an icon plus accessibility label; network-name text does not clutter normal inbox rows.
- One account is allowed per user-facing service.
- Manual linking only: Pallo never automatically merges or suggests contacts.
- Linked people open a contact summary first; every remote conversation remains separate.
- The composer sends only to the explicitly opened remote conversation and never switches platforms automatically.
- The main window may close while the menu-bar app remains active; Quit terminates the process.
- No feeds, posts, Stories, status publishing, calls, analytics, Pallo cloud, or real network credentials belong in this plan.
- No Synapse, Matrix SDK, real bridge, media download, update, or packaging implementation belongs in this plan; those integrate through the interfaces defined here.
- All production types use explicit stable IDs and `Sendable` value semantics where applicable.
- Tests are written before implementation and every task ends with a focused commit.

## File and module map

```text
Package.swift                                      Swift package and executable declaration
LICENSE                                            Canonical AGPL-3.0 license text
README.md                                          Development commands and vertical-slice scope
Sources/PalloApp/PalloApp.swift                    SwiftUI app, WindowGroup, MenuBarExtra, Quit action
Sources/PalloCore/Platform.swift                   Platform identity, icon metadata, one-account key
Sources/PalloCore/MessagingModels.swift            Accounts, remote identities/conversations, messages
Sources/PalloCore/ContactModels.swift              PalloPerson and explicit PersonLink
Sources/PalloGateway/Module.swift                  Temporary target marker removed in Task 2
Sources/PalloGateway/MessagingGateway.swift        Gateway protocol, snapshots, events, send receipt
Sources/PalloGateway/InMemoryMessagingGateway.swift Deterministic actor-backed development gateway
Sources/PalloFeatures/Module.swift                 Temporary target marker removed in Task 3
Sources/PalloFeatures/ContactDirectory.swift       Manual link/unlink invariants
Sources/PalloFeatures/InboxProjector.swift         Unified inbox projection and ordering
Sources/PalloFeatures/PalloAppModel.swift           Main-actor navigation, sync, send and health state
Sources/PalloFeatures/Fixtures.swift                Shared deterministic preview/development data
Sources/PalloUI/Module.swift                       Temporary target marker removed in Task 6
Sources/PalloUI/PlatformBadge.swift                 Accessible platform icon component
Sources/PalloUI/NavigationRailView.swift            Narrow Pallo navigation rail
Sources/PalloUI/InboxView.swift                     Inbox list and selection
Sources/PalloUI/ContactSummaryView.swift            Cards for linked remote conversations
Sources/PalloUI/LinkPersonSheet.swift               Explicit existing/new person linking flow
Sources/PalloUI/ConversationView.swift              Timeline, composer, send failure state
Sources/PalloUI/RootView.swift                      Approved three-pane composition
Sources/PalloUI/MenuBarContentView.swift            Compact background health/actions
Tests/PalloCoreTests/MessagingModelsTests.swift     Stable route and platform invariants
Tests/PalloGatewayTests/InMemoryGatewayTests.swift  Gateway snapshots, stream and acknowledgement
Tests/PalloFeaturesTests/ContactDirectoryTests.swift Manual link/unlink behavior
Tests/PalloFeaturesTests/InboxProjectorTests.swift  Deduplication, latest activity and unread sums
Tests/PalloFeaturesTests/PalloAppModelTests.swift    Navigation and exact-route send behavior
Tests/PalloUITests/AccessibilityModelTests.swift    Icon labels and UI presentation invariants
```

The package has five targets so each unit has one clear dependency direction:

```text
PalloCore ← PalloGateway ← PalloFeatures ← PalloUI ← PalloApp
```

---

### Task 1: Establish the native Swift package and domain primitives

**Files:**
- Create: `Package.swift`
- Create: `LICENSE`
- Create: `README.md`
- Create: `Sources/PalloCore/Platform.swift`
- Create: `Sources/PalloCore/MessagingModels.swift`
- Create: `Sources/PalloCore/ContactModels.swift`
- Create: `Sources/PalloGateway/Module.swift`
- Create: `Sources/PalloFeatures/Module.swift`
- Create: `Sources/PalloUI/Module.swift`
- Create: `Sources/PalloApp/main.swift`
- Test: `Tests/PalloCoreTests/MessagingModelsTests.swift`

**Interfaces:**
- Consumes: None.
- Produces: `Platform`, `ConnectedAccount`, `RemoteIdentity`, `RemoteConversation`, `Message`, `MessageDeliveryState`, `PalloPerson`, and `PersonLink` for all later tasks.

- [ ] **Step 1: Write the package manifest and failing domain tests**

Create `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pallo",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Pallo", targets: ["PalloApp"])],
    targets: [
        .target(name: "PalloCore"),
        .target(name: "PalloGateway", dependencies: ["PalloCore"]),
        .target(name: "PalloFeatures", dependencies: ["PalloCore", "PalloGateway"]),
        .target(name: "PalloUI", dependencies: ["PalloCore", "PalloFeatures"]),
        .executableTarget(name: "PalloApp", dependencies: ["PalloGateway", "PalloFeatures", "PalloUI"]),
        .testTarget(name: "PalloCoreTests", dependencies: ["PalloCore"]),
    ]
)
```

Create `Tests/PalloCoreTests/MessagingModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import PalloCore

@Test func everyPlatformHasAccessibleIconMetadata() {
    for platform in Platform.allCases {
        #expect(!platform.accessibilityLabel.isEmpty)
        #expect(!platform.symbolName.isEmpty)
    }
}

@Test func conversationRouteIncludesAccountAndRemoteID() {
    let account = ConnectedAccount(id: "whatsapp-primary", platform: .whatsApp, displayName: "Personal")
    let identity = RemoteIdentity(id: "maya-wa", accountID: account.id, displayName: "Maya")
    let conversation = RemoteConversation(
        id: "wa-chat-42",
        accountID: account.id,
        identityID: identity.id,
        title: "Maya",
        latestActivity: Date(timeIntervalSince1970: 10),
        unreadCount: 2
    )

    #expect(conversation.route == ConversationRoute(accountID: "whatsapp-primary", conversationID: "wa-chat-42"))
}

@Test func personLinkContainsOnlyExplicitRemoteIdentities() {
    let link = PersonLink(personID: "maya", remoteIdentityIDs: ["maya-wa", "maya-ig"])
    #expect(link.remoteIdentityIDs == ["maya-wa", "maya-ig"])
}

@Test func accountPolicyRejectsTwoAccountsForOnePlatform() {
    let accounts = [
        ConnectedAccount(id: "wa-1", platform: .whatsApp, displayName: "One"),
        ConnectedAccount(id: "wa-2", platform: .whatsApp, displayName: "Two")
    ]
    #expect(throws: AccountPolicyError.duplicatePlatform(.whatsApp)) {
        try AccountPolicy.validate(accounts)
    }
}
```

Create the future target markers so the complete package manifest builds from the first commit:

```swift
// Sources/PalloGateway/Module.swift
public enum PalloGatewayModule {}

// Sources/PalloFeatures/Module.swift
public enum PalloFeaturesModule {}

// Sources/PalloUI/Module.swift
public enum PalloUIModule {}

// Sources/PalloApp/main.swift
print("Pallo vertical slice")

```

- [ ] **Step 2: Run the domain tests and verify they fail**

Run:

```bash
swift test --filter PalloCoreTests
```

Expected: compilation fails because `Platform`, `ConnectedAccount`, `RemoteIdentity`, `RemoteConversation`, `ConversationRoute`, and `PersonLink` do not exist.

- [ ] **Step 3: Implement the minimal domain model**

Create `Sources/PalloCore/Platform.swift`:

```swift
public enum Platform: String, CaseIterable, Codable, Hashable, Sendable {
    case whatsApp, instagram, facebookMessenger, telegram, signal, discord
    case slack, x, linkedIn, googleMessages, googleChat, googleVoice
    case iMessage, matrix, irc, bluesky

    public var accessibilityLabel: String {
        switch self {
        case .whatsApp: "WhatsApp"
        case .instagram: "Instagram"
        case .facebookMessenger: "Facebook Messenger"
        case .telegram: "Telegram"
        case .signal: "Signal"
        case .discord: "Discord"
        case .slack: "Slack"
        case .x: "X"
        case .linkedIn: "LinkedIn"
        case .googleMessages: "Google Messages"
        case .googleChat: "Google Chat"
        case .googleVoice: "Google Voice"
        case .iMessage: "iMessage"
        case .matrix: "Matrix"
        case .irc: "IRC"
        case .bluesky: "Bluesky"
        }
    }

    public var symbolName: String {
        switch self {
        case .iMessage, .googleMessages: "message.fill"
        case .instagram: "camera.fill"
        case .telegram: "paperplane.fill"
        case .discord, .slack, .googleChat, .irc: "bubble.left.and.bubble.right.fill"
        case .googleVoice: "phone.fill"
        case .linkedIn: "person.crop.square.fill"
        case .bluesky: "cloud.fill"
        default: "message.circle.fill"
        }
    }
}
```

Create `Sources/PalloCore/MessagingModels.swift`:

```swift
import Foundation

public struct ConnectedAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let platform: Platform
    public var displayName: String

    public init(id: String, platform: Platform, displayName: String) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
    }
}

public enum AccountPolicyError: Error, Equatable {
    case duplicatePlatform(Platform)
}

public enum AccountPolicy {
    public static func validate(_ accounts: [ConnectedAccount]) throws {
        var seen: Set<Platform> = []
        for account in accounts where !seen.insert(account.platform).inserted {
            throw AccountPolicyError.duplicatePlatform(account.platform)
        }
    }
}

public struct RemoteIdentity: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public var displayName: String

    public init(id: String, accountID: String, displayName: String) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
    }
}

public struct ConversationRoute: Codable, Hashable, Sendable {
    public let accountID: String
    public let conversationID: String

    public init(accountID: String, conversationID: String) {
        self.accountID = accountID
        self.conversationID = conversationID
    }
}

public struct RemoteConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let identityID: String
    public var title: String
    public var latestPreview: String
    public var latestActivity: Date
    public var unreadCount: Int

    public var route: ConversationRoute { .init(accountID: accountID, conversationID: id) }

    public init(id: String, accountID: String, identityID: String, title: String, latestPreview: String = "", latestActivity: Date, unreadCount: Int) {
        self.id = id
        self.accountID = accountID
        self.identityID = identityID
        self.title = title
        self.latestPreview = latestPreview
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
    }
}

public enum MessageDeliveryState: Codable, Hashable, Sendable { case pending, acknowledged, failed(String) }

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let route: ConversationRoute
    public let senderIdentityID: String?
    public var body: String
    public let timestamp: Date
    public var deliveryState: MessageDeliveryState

    public init(id: String, route: ConversationRoute, senderIdentityID: String?, body: String, timestamp: Date, deliveryState: MessageDeliveryState) {
        self.id = id
        self.route = route
        self.senderIdentityID = senderIdentityID
        self.body = body
        self.timestamp = timestamp
        self.deliveryState = deliveryState
    }
}
```

Create `Sources/PalloCore/ContactModels.swift`:

```swift
public struct PalloPerson: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct PersonLink: Codable, Equatable, Sendable {
    public let personID: String
    public var remoteIdentityIDs: Set<String>

    public init(personID: String, remoteIdentityIDs: Set<String>) {
        self.personID = personID
        self.remoteIdentityIDs = remoteIdentityIDs
    }
}
```

- [ ] **Step 4: Add the development README**

Create the canonical AGPL-3.0 license file and verify its title:

```bash
curl --fail --location https://www.gnu.org/licenses/agpl-3.0.txt --output LICENSE
head -n 2 LICENSE
```

Expected second line: `GNU AFFERO GENERAL PUBLIC LICENSE`. If the download fails or the title differs, stop rather than committing an incomplete or different license.

Create `README.md` with these exact sections:

````markdown
# Pallo

Pallo is a local-first universal messaging inbox for macOS. This repository currently contains the native vertical slice described in `docs/superpowers/plans/2026-08-12-pallo-native-vertical-slice.md`.

## Requirements

- Apple silicon Mac
- macOS 15 or later
- Xcode 26.5 or a compatible Swift 6.3 toolchain

## Commands

```bash
swift build
swift test
swift run Pallo
```

The first slice uses deterministic local fixtures. It does not connect real accounts or include Synapse yet.
````

- [ ] **Step 5: Run tests and build**

Run:

```bash
swift test --filter PalloCoreTests
swift build
```

Expected: all three domain tests pass and all five targets compile.

- [ ] **Step 6: Commit the domain foundation**

```bash
git add Package.swift LICENSE README.md Sources Tests
git commit -m "feat: establish Pallo domain foundation"
```

### Task 2: Define the messaging boundary and deterministic gateway

**Files:**
- Create: `Sources/PalloGateway/MessagingGateway.swift`
- Create: `Sources/PalloGateway/InMemoryMessagingGateway.swift`
- Delete: `Sources/PalloGateway/Module.swift`
- Modify: `Package.swift`
- Test: `Tests/PalloGatewayTests/InMemoryGatewayTests.swift`

**Interfaces:**
- Consumes: `ConnectedAccount`, `RemoteIdentity`, `RemoteConversation`, `ConversationRoute`, and `Message` from Task 1.
- Produces: `MessagingSnapshot`, `GatewayEvent`, `SendReceipt`, `MessagingGateway`, and `InMemoryMessagingGateway` used by Tasks 4–7.

- [ ] **Step 1: Write failing gateway tests**

Add the first real gateway test target to `Package.swift`:

```swift
.testTarget(name: "PalloGatewayTests", dependencies: ["PalloCore", "PalloGateway"]),
```

Create `Tests/PalloGatewayTests/InMemoryGatewayTests.swift`:

```swift
import Foundation
import Testing
@testable import PalloCore
@testable import PalloGateway

@Test func snapshotReturnsSeededRecords() async throws {
    let route = ConversationRoute(accountID: "telegram-primary", conversationID: "family")
    let gateway = InMemoryMessagingGateway(seed: .init(
        accounts: [.init(id: route.accountID, platform: .telegram, displayName: "Personal")],
        identities: [.init(id: "family-id", accountID: route.accountID, displayName: "Family")],
        conversations: [.init(id: route.conversationID, accountID: route.accountID, identityID: "family-id", title: "Family", latestActivity: .distantPast, unreadCount: 1)],
        messagesByRoute: [route: []]
    ))

    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.conversations.first?.route == route)
}

@Test func sendAcknowledgesTheExactRouteAndPublishesEvent() async throws {
    let expected = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-ig")
    let gateway = InMemoryMessagingGateway(seed: .empty)
    let stream = await gateway.events()

    let receipt = try await gateway.sendText("Hello", to: expected)
    #expect(receipt.route == expected)
    #expect(receipt.deliveryState == .acknowledged)

    for await event in stream {
        guard case let .messageUpserted(message) = event else { continue }
        #expect(message.route == expected)
        #expect(message.body == "Hello")
        break
    }
}
```

- [ ] **Step 2: Run the gateway tests and verify they fail**

Run: `swift test --filter PalloGatewayTests`

Expected: compilation fails because the gateway types do not exist.

- [ ] **Step 3: Define the protocol and event types**

Create `Sources/PalloGateway/MessagingGateway.swift`:

```swift
import PalloCore

public struct MessagingSnapshot: Sendable {
    public var accounts: [ConnectedAccount]
    public var identities: [RemoteIdentity]
    public var conversations: [RemoteConversation]
    public var messagesByRoute: [ConversationRoute: [Message]]

    public init(accounts: [ConnectedAccount], identities: [RemoteIdentity], conversations: [RemoteConversation], messagesByRoute: [ConversationRoute: [Message]]) {
        self.accounts = accounts
        self.identities = identities
        self.conversations = conversations
        self.messagesByRoute = messagesByRoute
    }

    public static let empty = Self(accounts: [], identities: [], conversations: [], messagesByRoute: [:])
}

public enum GatewayEvent: Sendable {
    case messageUpserted(Message)
    case conversationUpserted(RemoteConversation)
    case connectionChanged(accountID: String, isConnected: Bool)
}

public struct SendReceipt: Sendable {
    public let messageID: String
    public let route: ConversationRoute
    public let deliveryState: MessageDeliveryState

    public init(messageID: String, route: ConversationRoute, deliveryState: MessageDeliveryState) {
        self.messageID = messageID
        self.route = route
        self.deliveryState = deliveryState
    }
}

public protocol MessagingGateway: Sendable {
    func loadSnapshot() async throws -> MessagingSnapshot
    func events() async -> AsyncStream<GatewayEvent>
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt
}
```

- [ ] **Step 4: Implement the actor-backed in-memory gateway**

Create `Sources/PalloGateway/InMemoryMessagingGateway.swift`:

```swift
import Foundation
import PalloCore

public actor InMemoryMessagingGateway: MessagingGateway {
    private var snapshot: MessagingSnapshot
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]

    public init(seed: MessagingSnapshot) { snapshot = seed }

    public func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    public func events() async -> AsyncStream<GatewayEvent> {
        let id = UUID()
        let pair = AsyncStream<GatewayEvent>.makeStream()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return pair.stream
    }

    public func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        let message = Message(
            id: UUID().uuidString,
            route: route,
            senderIdentityID: nil,
            body: body,
            timestamp: Date(),
            deliveryState: .acknowledged
        )
        snapshot.messagesByRoute[route, default: []].append(message)
        continuations.values.forEach { $0.yield(.messageUpserted(message)) }
        return SendReceipt(messageID: message.id, route: route, deliveryState: message.deliveryState)
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}
```

Delete the no-longer-needed `Sources/PalloGateway/Module.swift` target marker.

- [ ] **Step 5: Run gateway and full tests**

Run:

```bash
swift test --filter PalloGatewayTests
swift test
```

Expected: both gateway tests and all prior tests pass.

- [ ] **Step 6: Commit the gateway boundary**

```bash
git add Sources/PalloGateway Tests/PalloGatewayTests
git commit -m "feat: add deterministic messaging gateway"
```

### Task 3: Implement explicit contact linking

**Files:**
- Create: `Sources/PalloFeatures/ContactDirectory.swift`
- Delete: `Sources/PalloFeatures/Module.swift`
- Modify: `Package.swift`
- Test: `Tests/PalloFeaturesTests/ContactDirectoryTests.swift`

**Interfaces:**
- Consumes: `PalloPerson`, `PersonLink`, and stable remote identity IDs.
- Produces: `ContactDirectory`, `ContactDirectoryError`, `createPerson(id:displayName:)`, `link(remoteIdentityID:to:)`, `unlink(remoteIdentityID:from:)`, and `personID(linkedTo:)` for Tasks 4–7.

- [ ] **Step 1: Write failing manual-link tests**

Add the first real feature test target to `Package.swift`:

```swift
.testTarget(name: "PalloFeaturesTests", dependencies: ["PalloCore", "PalloGateway", "PalloFeatures"]),
```

Create `Tests/PalloFeaturesTests/ContactDirectoryTests.swift`:

```swift
import Testing
@testable import PalloCore
@testable import PalloFeatures

@Test func identitiesRemainUnlinkedUntilExplicitAction() throws {
    let directory = ContactDirectory()
    #expect(directory.personID(linkedTo: "maya-wa") == nil)
}

@Test func explicitLinkAndUnlinkDoNotDeleteThePerson() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")
    #expect(directory.personID(linkedTo: "maya-wa") == "maya")

    try directory.unlink(remoteIdentityID: "maya-wa", from: "maya")
    #expect(directory.personID(linkedTo: "maya-wa") == nil)
    #expect(directory.people["maya"]?.displayName == "Maya")
}

@Test func oneRemoteIdentityCannotBelongToTwoPeople() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.createPerson(id: "other", displayName: "Other")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")

    #expect(throws: ContactDirectoryError.identityAlreadyLinked) {
        try directory.link(remoteIdentityID: "maya-wa", to: "other")
    }
}

@Test func removingNewPersonAlsoRemovesItsEmptyLinkRecord() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "temporary", displayName: "Temporary")
    directory.removePerson(id: "temporary")
    #expect(directory.people["temporary"] == nil)
    #expect(directory.links["temporary"] == nil)
}
```

Delete the no-longer-needed `Sources/PalloFeatures/Module.swift` target marker.

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter ContactDirectoryTests`

Expected: compilation fails because `ContactDirectory` and `ContactDirectoryError` do not exist.

- [ ] **Step 3: Implement manual linking invariants**

Create `Sources/PalloFeatures/ContactDirectory.swift`:

```swift
import PalloCore

public enum ContactDirectoryError: Error, Equatable {
    case duplicatePerson
    case missingPerson
    case identityAlreadyLinked
}

public struct ContactDirectory: Sendable {
    public private(set) var people: [String: PalloPerson]
    public private(set) var links: [String: PersonLink]

    public init(people: [String: PalloPerson] = [:], links: [String: PersonLink] = [:]) {
        self.people = people
        self.links = links
    }

    public mutating func createPerson(id: String, displayName: String) throws {
        guard people[id] == nil else { throw ContactDirectoryError.duplicatePerson }
        people[id] = PalloPerson(id: id, displayName: displayName)
    }

    public mutating func link(remoteIdentityID: String, to personID: String) throws {
        guard people[personID] != nil else { throw ContactDirectoryError.missingPerson }
        guard self.personID(linkedTo: remoteIdentityID) == nil else { throw ContactDirectoryError.identityAlreadyLinked }
        var link = links[personID] ?? PersonLink(personID: personID, remoteIdentityIDs: [])
        link.remoteIdentityIDs.insert(remoteIdentityID)
        links[personID] = link
    }

    public mutating func unlink(remoteIdentityID: String, from personID: String) throws {
        guard var link = links[personID] else { throw ContactDirectoryError.missingPerson }
        link.remoteIdentityIDs.remove(remoteIdentityID)
        links[personID] = link
    }

    mutating func removePerson(id: String) {
        people[id] = nil
        links[id] = nil
    }

    public func personID(linkedTo remoteIdentityID: String) -> String? {
        links.values.first { $0.remoteIdentityIDs.contains(remoteIdentityID) }?.personID
    }
}
```

- [ ] **Step 4: Run contact tests and all tests**

Run:

```bash
swift test --filter ContactDirectoryTests
swift test
```

Expected: all contact and prior tests pass.

- [ ] **Step 5: Commit explicit contact linking**

```bash
git add Sources/PalloFeatures/ContactDirectory.swift Tests/PalloFeaturesTests/ContactDirectoryTests.swift
git commit -m "feat: add explicit contact linking"
```

### Task 4: Project remote conversations into one unified inbox

**Files:**
- Create: `Sources/PalloFeatures/InboxProjector.swift`
- Test: `Tests/PalloFeaturesTests/InboxProjectorTests.swift`

**Interfaces:**
- Consumes: `ConnectedAccount`, `RemoteIdentity`, `RemoteConversation`, `ContactDirectory`.
- Produces: `InboxItem`, `ConversationSummary`, and `InboxProjector.project(...)` used by `PalloAppModel` and the UI.

- [ ] **Step 1: Write failing inbox projection tests**

Create `Tests/PalloFeaturesTests/InboxProjectorTests.swift` with fixtures local to the test:

```swift
import Foundation
import Testing
@testable import PalloCore
@testable import PalloFeatures

@Test func linkedIdentitiesBecomeOneInboxPersonWithSummedUnread() throws {
    let accounts = [
        ConnectedAccount(id: "wa", platform: .whatsApp, displayName: "Personal"),
        ConnectedAccount(id: "ig", platform: .instagram, displayName: "Personal")
    ]
    let identities = [
        RemoteIdentity(id: "maya-wa", accountID: "wa", displayName: "Maya"),
        RemoteIdentity(id: "maya-ig", accountID: "ig", displayName: "@maya")
    ]
    let conversations = [
        RemoteConversation(id: "wa-chat", accountID: "wa", identityID: "maya-wa", title: "Maya", latestActivity: Date(timeIntervalSince1970: 10), unreadCount: 2),
        RemoteConversation(id: "ig-chat", accountID: "ig", identityID: "maya-ig", title: "@maya", latestActivity: Date(timeIntervalSince1970: 20), unreadCount: 3)
    ]
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")
    try directory.link(remoteIdentityID: "maya-ig", to: "maya")

    let result = InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations, directory: directory)
    #expect(result.count == 1)
    #expect(result[0].id == .person("maya"))
    #expect(result[0].unreadCount == 5)
    #expect(result[0].conversationSummaries.map(\.route) == [
        ConversationRoute(accountID: "ig", conversationID: "ig-chat"),
        ConversationRoute(accountID: "wa", conversationID: "wa-chat")
    ])
}

@Test func unlinkedConversationRemainsStandalone() {
    let account = ConnectedAccount(id: "tg", platform: .telegram, displayName: "Personal")
    let identity = RemoteIdentity(id: "family", accountID: "tg", displayName: "Family")
    let conversation = RemoteConversation(id: "family-chat", accountID: "tg", identityID: "family", title: "Family", latestActivity: .distantPast, unreadCount: 1)

    let result = InboxProjector.project(accounts: [account], identities: [identity], conversations: [conversation], directory: ContactDirectory())
    #expect(result.map(\.id) == [.conversation(conversation.route)])
}
```

- [ ] **Step 2: Run the projector tests and verify they fail**

Run: `swift test --filter InboxProjectorTests`

Expected: compilation fails because projection types do not exist.

- [ ] **Step 3: Implement the projection types and deterministic ordering**

Create `Sources/PalloFeatures/InboxProjector.swift`:

```swift
import Foundation
import PalloCore

public struct ConversationSummary: Identifiable, Hashable, Sendable {
    public var id: ConversationRoute { route }
    public let route: ConversationRoute
    public let platform: Platform
    public let title: String
    public let latestPreview: String
    public let latestActivity: Date
    public let unreadCount: Int
}

public struct InboxItem: Identifiable, Hashable, Sendable {
    public enum ID: Hashable, Sendable { case person(String), conversation(ConversationRoute) }
    public let id: ID
    public let title: String
    public let latestActivity: Date
    public let unreadCount: Int
    public let conversationSummaries: [ConversationSummary]
}

public enum InboxProjector {
    public static func project(
        accounts: [ConnectedAccount],
        identities: [RemoteIdentity],
        conversations: [RemoteConversation],
        directory: ContactDirectory
    ) -> [InboxItem] {
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let identityByID = Dictionary(uniqueKeysWithValues: identities.map { ($0.id, $0) })
        let summaries = conversations.compactMap { conversation -> (RemoteIdentity, ConversationSummary)? in
            guard let identity = identityByID[conversation.identityID], let account = accountByID[conversation.accountID] else { return nil }
            return (identity, ConversationSummary(route: conversation.route, platform: account.platform, title: conversation.title, latestPreview: conversation.latestPreview, latestActivity: conversation.latestActivity, unreadCount: conversation.unreadCount))
        }

        var grouped: [InboxItem.ID: [ConversationSummary]] = [:]
        for (identity, summary) in summaries {
            let id = directory.personID(linkedTo: identity.id).map(InboxItem.ID.person) ?? .conversation(summary.route)
            grouped[id, default: []].append(summary)
        }

        return grouped.map { id, values in
            let sorted = values.sorted { $0.latestActivity > $1.latestActivity }
            let title: String
            switch id {
            case let .person(personID): title = directory.people[personID]?.displayName ?? sorted[0].title
            case .conversation: title = sorted[0].title
            }
            return InboxItem(id: id, title: title, latestActivity: sorted[0].latestActivity, unreadCount: sorted.reduce(0) { $0 + $1.unreadCount }, conversationSummaries: sorted)
        }.sorted {
            if $0.latestActivity == $1.latestActivity { return String(describing: $0.id) < String(describing: $1.id) }
            return $0.latestActivity > $1.latestActivity
        }
    }
}
```

- [ ] **Step 4: Run projector and full tests**

Run:

```bash
swift test --filter InboxProjectorTests
swift test
```

Expected: linked Maya appears once, conversations are newest-first, unread is `5`, and the unlinked chat remains standalone.

- [ ] **Step 5: Commit the inbox projection**

```bash
git add Sources/PalloFeatures/InboxProjector.swift Tests/PalloFeaturesTests/InboxProjectorTests.swift
git commit -m "feat: project linked contacts into unified inbox"
```

### Task 5: Build application state with exact-route sending

**Files:**
- Create: `Sources/PalloFeatures/Fixtures.swift`
- Create: `Sources/PalloFeatures/PalloAppModel.swift`
- Test: `Tests/PalloFeaturesTests/PalloAppModelTests.swift`

**Interfaces:**
- Consumes: `MessagingGateway`, `ContactDirectory`, `InboxProjector`, and all domain models.
- Produces: `PalloAppModel`, `DetailSelection`, `ServiceHealth`, `start()`, `selectInboxItem(_:)`, `openConversation(_:)`, `sendDraft()`, `linkOpenConversation(to:)`, `createPersonAndLinkOpenConversation(displayName:)`, and observable state for Tasks 6–7.

- [ ] **Step 1: Write failing route-safety and navigation tests**

Create `Tests/PalloFeaturesTests/PalloAppModelTests.swift`:

```swift
import Testing
@testable import PalloCore
@testable import PalloGateway
@testable import PalloFeatures

@MainActor
@Test func linkedPersonOpensSummaryBeforeConversation() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    let person = try #require(model.inboxItems.first { $0.id == .person("maya") })
    model.selectInboxItem(person)
    #expect(model.detailSelection == .personSummary("maya"))
}

@MainActor
@Test func sendingUsesOnlyTheExplicitlyOpenedRoute() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let instagram = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-instagram")
    let whatsApp = ConversationRoute(accountID: "whatsapp-primary", conversationID: "maya-whatsapp")
    let whatsAppCountBefore = (try await gateway.loadSnapshot()).messagesByRoute[whatsApp]?.count

    model.openConversation(instagram)
    model.draft = "Sent through Instagram"
    try await model.sendDraft()

    #expect(model.openRoute == instagram)
    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.messagesByRoute[instagram]?.last?.body == "Sent through Instagram")
    #expect(snapshot.messagesByRoute[whatsApp]?.count == whatsAppCountBefore)
}

@MainActor
@Test func userCanExplicitlyLinkAnOpenStandaloneConversation() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)

    let personID = try model.createPersonAndLinkOpenConversation(displayName: "Family")

    #expect(model.detailSelection == .personSummary(personID))
    #expect(model.inboxItems.first { $0.id == .person(personID) }?.conversationSummaries.map(\.route) == [Fixtures.telegramRoute])
}
```

- [ ] **Step 2: Run app-model tests and verify they fail**

Run: `swift test --filter PalloAppModelTests`

Expected: compilation fails because `Fixtures` and `PalloAppModel` do not exist.

Before implementation, add regression coverage proving that:

- a second `.messageUpserted` event with the same route and message ID replaces the existing value (for example, updating delivery state) without creating a duplicate;
- connection health aggregates all validated account IDs, so reconnecting one of two disconnected accounts remains unhealthy until both reconnect, while events for unknown accounts are ignored; and
- calling `start()` repeatedly leaves exactly one active event subscription, while `stop()` cancels it.

- [ ] **Step 3: Create deterministic feature fixtures**

Create `Sources/PalloFeatures/Fixtures.swift`:

```swift
import Foundation
import PalloCore
import PalloGateway

public enum Fixtures {
    public static let whatsAppRoute = ConversationRoute(accountID: "whatsapp-primary", conversationID: "maya-whatsapp")
    public static let instagramRoute = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-instagram")
    public static let telegramRoute = ConversationRoute(accountID: "telegram-primary", conversationID: "family-telegram")

    public static let snapshot = MessagingSnapshot(
        accounts: [
            .init(id: "whatsapp-primary", platform: .whatsApp, displayName: "Personal"),
            .init(id: "instagram-primary", platform: .instagram, displayName: "Personal"),
            .init(id: "telegram-primary", platform: .telegram, displayName: "Personal")
        ],
        identities: [
            .init(id: "maya-whatsapp-identity", accountID: "whatsapp-primary", displayName: "Maya"),
            .init(id: "maya-instagram-identity", accountID: "instagram-primary", displayName: "@maya"),
            .init(id: "family-telegram-identity", accountID: "telegram-primary", displayName: "Family")
        ],
        conversations: [
            .init(id: "maya-whatsapp", accountID: "whatsapp-primary", identityID: "maya-whatsapp-identity", title: "Maya", latestPreview: "Are we still meeting tonight?", latestActivity: Date(timeIntervalSince1970: 200), unreadCount: 1),
            .init(id: "maya-instagram", accountID: "instagram-primary", identityID: "maya-instagram-identity", title: "@maya", latestPreview: "I sent the address here.", latestActivity: Date(timeIntervalSince1970: 300), unreadCount: 2),
            .init(id: "family-telegram", accountID: "telegram-primary", identityID: "family-telegram-identity", title: "Family", latestPreview: "Dinner this weekend?", latestActivity: Date(timeIntervalSince1970: 100), unreadCount: 0)
        ],
        messagesByRoute: [
            whatsAppRoute: [.init(id: "wa-1", route: whatsAppRoute, senderIdentityID: "maya-whatsapp-identity", body: "Are we still meeting tonight?", timestamp: Date(timeIntervalSince1970: 200), deliveryState: .acknowledged)],
            instagramRoute: [.init(id: "ig-1", route: instagramRoute, senderIdentityID: "maya-instagram-identity", body: "I sent the address here.", timestamp: Date(timeIntervalSince1970: 300), deliveryState: .acknowledged)],
            telegramRoute: [.init(id: "tg-1", route: telegramRoute, senderIdentityID: "family-telegram-identity", body: "Dinner this weekend?", timestamp: Date(timeIntervalSince1970: 100), deliveryState: .acknowledged)]
        ]
    )

    public static var directory: ContactDirectory {
        var value = ContactDirectory()
        try! value.createPerson(id: "maya", displayName: "Maya")
        try! value.link(remoteIdentityID: "maya-whatsapp-identity", to: "maya")
        try! value.link(remoteIdentityID: "maya-instagram-identity", to: "maya")
        return value
    }
}
```

- [ ] **Step 4: Implement the observable app model**

Create `Sources/PalloFeatures/PalloAppModel.swift`:

```swift
import Observation
import PalloCore
import PalloGateway

public enum DetailSelection: Equatable, Sendable {
    case empty
    case personSummary(String)
    case conversation(ConversationRoute)
}

public enum ServiceHealth: Equatable, Sendable { case starting, healthy, needsAttention(String) }

@MainActor
@Observable
public final class PalloAppModel {
    public private(set) var accounts: [ConnectedAccount] = []
    public private(set) var identities: [RemoteIdentity] = []
    public private(set) var conversations: [RemoteConversation] = []
    public private(set) var messagesByRoute: [ConversationRoute: [Message]] = [:]
    public private(set) var inboxItems: [InboxItem] = []
    public private(set) var detailSelection: DetailSelection = .empty
    public private(set) var health: ServiceHealth = .starting
    public var draft = ""

    public var openRoute: ConversationRoute? {
        guard case let .conversation(route) = detailSelection else { return nil }
        return route
    }

    private let gateway: any MessagingGateway
    private var directory: ContactDirectory
    private var disconnectedAccountIDs: Set<String> = []
    private var eventTask: Task<Void, Never>?

    public init(gateway: any MessagingGateway, directory: ContactDirectory = .init()) {
        self.gateway = gateway
        self.directory = directory
    }

    public func start() async throws {
        eventTask?.cancel()
        let snapshot = try await gateway.loadSnapshot()
        try AccountPolicy.validate(snapshot.accounts)
        apply(snapshot)
        disconnectedAccountIDs.removeAll()
        health = .healthy
        let stream = await gateway.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.apply(event)
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    deinit { eventTask?.cancel() }

    public func selectInboxItem(_ item: InboxItem) {
        switch item.id {
        case let .person(id): detailSelection = .personSummary(id)
        case let .conversation(route): detailSelection = .conversation(route)
        }
    }

    public func openConversation(_ route: ConversationRoute) { detailSelection = .conversation(route) }

    public func sendDraft() async throws {
        guard let route = openRoute else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try await gateway.sendText(body, to: route)
        draft = ""
    }

    public func summaries(for personID: String) -> [ConversationSummary] {
        inboxItems.first { $0.id == .person(personID) }?.conversationSummaries ?? []
    }

    public var people: [PalloPerson] {
        directory.people.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func personID(for route: ConversationRoute) -> String? {
        guard let identityID = conversations.first(where: { $0.route == route })?.identityID else { return nil }
        return directory.personID(linkedTo: identityID)
    }

    public func linkOpenConversation(to personID: String) throws {
        guard let route = openRoute,
              let identityID = conversations.first(where: { $0.route == route })?.identityID
        else { return }
        try directory.link(remoteIdentityID: identityID, to: personID)
        rebuildInbox()
        detailSelection = .personSummary(personID)
    }

    @discardableResult
    public func createPersonAndLinkOpenConversation(displayName: String) throws -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactDirectoryError.missingPerson }
        let personID = UUID().uuidString
        try directory.createPerson(id: personID, displayName: trimmed)
        do { try linkOpenConversation(to: personID) }
        catch {
            directory.removePerson(id: personID)
            throw error
        }
        return personID
    }

    private func apply(_ snapshot: MessagingSnapshot) {
        accounts = snapshot.accounts
        identities = snapshot.identities
        conversations = snapshot.conversations
        messagesByRoute = snapshot.messagesByRoute
        rebuildInbox()
    }

    private func apply(_ event: GatewayEvent) {
        switch event {
        case let .messageUpserted(message):
            var messages = messagesByRoute[message.route, default: []]
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            else { messages.append(message) }
            messagesByRoute[message.route] = messages
        case let .conversationUpserted(conversation):
            conversations.removeAll { $0.id == conversation.id && $0.accountID == conversation.accountID }
            conversations.append(conversation)
            rebuildInbox()
        case let .connectionChanged(accountID, isConnected):
            guard accounts.contains(where: { $0.id == accountID }) else { return }
            if isConnected { disconnectedAccountIDs.remove(accountID) }
            else { disconnectedAccountIDs.insert(accountID) }
            health = disconnectedAccountIDs.isEmpty ? .healthy : .needsAttention("\(disconnectedAccountIDs.count) account(s) disconnected")
        }
    }

    private func rebuildInbox() {
        inboxItems = InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations, directory: directory)
    }
}
```

- [ ] **Step 5: Run app-model and full tests**

Run:

```bash
swift test --filter PalloAppModelTests
swift test
```

Expected: linked Maya opens `.personSummary("maya")`; the outgoing text appears only on the Instagram route; all tests pass.

- [ ] **Step 6: Commit application behavior**

```bash
git add Sources/PalloFeatures/Fixtures.swift Sources/PalloFeatures/PalloAppModel.swift Tests/PalloFeaturesTests/PalloAppModelTests.swift
git commit -m "feat: add route-safe Pallo application state"
```

### Task 6: Implement the approved three-pane SwiftUI experience

**Files:**
- Create: `Sources/PalloUI/PlatformBadge.swift`
- Create: `Sources/PalloUI/NavigationRailView.swift`
- Create: `Sources/PalloUI/InboxView.swift`
- Create: `Sources/PalloUI/ContactSummaryView.swift`
- Create: `Sources/PalloUI/LinkPersonSheet.swift`
- Create: `Sources/PalloUI/ConversationView.swift`
- Create: `Sources/PalloUI/RootView.swift`
- Delete: `Sources/PalloUI/Module.swift`
- Modify: `Package.swift`
- Test: `Tests/PalloUITests/AccessibilityModelTests.swift`

**Interfaces:**
- Consumes: `PalloAppModel`, `InboxItem`, `ConversationSummary`, `Platform`, `Message`, and `DetailSelection`.
- Produces: `RootView(model:)` and focused reusable SwiftUI views for Task 7.

- [ ] **Step 1: Write failing presentation-invariant tests**

Add the first real UI test target to `Package.swift`:

```swift
.testTarget(name: "PalloUITests", dependencies: ["PalloCore", "PalloFeatures", "PalloUI"]),
```

Create `Tests/PalloUITests/AccessibilityModelTests.swift`:

```swift
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
    let descriptor = ContactConversationCardDescriptor(route: route, platform: .whatsApp, title: "Latest message", preview: "Hello")
    #expect(descriptor.route == route)
    #expect(descriptor.accessibilityLabel.contains("WhatsApp"))
}
```

- [ ] **Step 2: Run UI tests and verify they fail**

Run: `swift test --filter PalloUITests`

Expected: compilation fails because UI descriptor types do not exist.

- [ ] **Step 3: Implement accessible platform badges and card descriptors**

Create `Sources/PalloUI/PlatformBadge.swift`:

```swift
import SwiftUI
import PalloCore

public struct PlatformBadgeDescriptor: Sendable {
    public let symbolName: String
    public let accessibilityLabel: String
    public init(platform: Platform) {
        symbolName = platform.symbolName
        accessibilityLabel = platform.accessibilityLabel
    }
}

public struct ContactConversationCardDescriptor: Sendable {
    public let route: ConversationRoute
    public let platform: Platform
    public let title: String
    public let preview: String
    public var accessibilityLabel: String { "\(platform.accessibilityLabel), \(title), \(preview)" }
    public init(route: ConversationRoute, platform: Platform, title: String, preview: String) {
        self.route = route; self.platform = platform; self.title = title; self.preview = preview
    }
}

public struct PlatformBadge: View {
    let platform: Platform
    public init(platform: Platform) { self.platform = platform }
    public var body: some View {
        let descriptor = PlatformBadgeDescriptor(platform: platform)
        Image(systemName: descriptor.symbolName)
            .frame(width: 18, height: 18)
            .accessibilityLabel(descriptor.accessibilityLabel)
            .help(descriptor.accessibilityLabel)
    }
}
```

Use SF Symbols in this vertical slice. The real-adapter plan adds trademark-reviewed SVG/asset-catalog network marks without changing `PlatformBadge` callers.

- [ ] **Step 4: Implement the navigation rail and inbox list**

Create `NavigationRailView.swift` as a fixed 54-point rail with a `P` mark, selected inbox button, search and contacts buttons, a spacer, and settings. Each icon must have `.accessibilityLabel` and `.help`.

```swift
import SwiftUI

struct NavigationRailView: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("P").font(.headline).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(.black, in: .rect(cornerRadius: 10))
                .accessibilityLabel("Pallo")
            railButton("tray.full.fill", label: "Inbox")
            railButton("magnifyingglass", label: "Search")
            railButton("person.2.fill", label: "Contacts")
            Spacer()
            railButton("gearshape.fill", label: "Settings")
        }
        .padding(.vertical, 14)
        .frame(width: 54)
    }

    private func railButton(_ symbol: String, label: String) -> some View {
        Button(action: {}) { Image(systemName: symbol).frame(width: 30, height: 30) }
            .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
```

Create `InboxView.swift` with this public API:

```swift
public struct InboxView: View {
    let items: [InboxItem]
    let onSelect: (InboxItem) -> Void
    public init(items: [InboxItem], onSelect: @escaping (InboxItem) -> Void)
}
```

Render `All` and `Unread` controls, newest-first rows, unread badge, timestamp, and one `PlatformBadge` for standalone conversations. For linked people with multiple summaries, show the icon of the newest summary plus a small `+N` accessibility-labelled indicator; do not print network names in the row.

Add this stable identifier helper to `InboxProjector.swift`:

```swift
public extension InboxItem.ID {
    var accessibilityIdentifier: String {
        switch self {
        case let .person(id): "person-\(id)"
        case let .conversation(route): "conversation-\(route.accountID)-\(route.conversationID)"
        }
    }
}
```

Implement the row from `InboxItem` data, not fixture-specific branches:

```swift
public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Inbox").font(.title2.bold())
        List(items) { item in
            Button { onSelect(item) } label: {
                HStack(spacing: 8) {
                    if let first = item.conversationSummaries.first {
                        PlatformBadge(platform: first.platform)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).fontWeight(.semibold)
                        Text(item.conversationSummaries.first?.latestPreview ?? "")
                            .lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.unreadCount > 0 { Text("\(item.unreadCount)").monospacedDigit() }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inbox-item-\(item.id.accessibilityIdentifier)")
        }
        .listStyle(.sidebar)
    }
    .padding(.top, 16)
    .accessibilityIdentifier("pallo-inbox")
}
```

Task 8 adds a focused test for this helper before final acceptance.

- [ ] **Step 5: Implement contact summary and conversation views**

Create `ContactSummaryView.swift` with:

```swift
public struct ContactSummaryView: View {
    let personName: String
    let summaries: [ConversationSummary]
    let onOpen: (ConversationRoute) -> Void
}
```

Each summary is a separate bordered card containing `PlatformBadge`, latest timestamp, unread count, and chevron. The complete card is a `Button` whose action passes the exact `summary.route`.

```swift
public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(personName).font(.title2.bold())
        Text("Choose a conversation").foregroundStyle(.secondary)
        ForEach(summaries) { summary in
            Button { onOpen(summary.route) } label: {
                HStack(spacing: 12) {
                    PlatformBadge(platform: summary.platform)
                    VStack(alignment: .leading) {
                        Text(summary.latestPreview).lineLimit(1)
                        Text(summary.latestActivity, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(12).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.quaternary) }
            .accessibilityLabel("\(summary.platform.accessibilityLabel), \(summary.latestPreview)")
            .accessibilityIdentifier("conversation-card-\(summary.route.accountID)-\(summary.route.conversationID)")
        }
        Spacer()
    }
    .padding(20)
    .accessibilityIdentifier("contact-summary")
}
```

Create `ConversationView.swift` with:

```swift
@Bindable var model: PalloAppModel
let route: ConversationRoute
```

Create `LinkPersonSheet.swift` with an explicit existing/new choice:

```swift
import SwiftUI
import PalloCore

struct LinkPersonSheet: View {
    let people: [PalloPerson]
    let onSelect: (String) -> Void
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link to person").font(.title2.bold())
            List(people) { person in
                Button(person.displayName) { onSelect(person.id); dismiss() }
            }.frame(minHeight: 120)
            Divider()
            TextField("New person’s name", text: $newName)
            Button("Create and link") { onCreate(newName); dismiss() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20).frame(width: 360)
    }
}
```

Look up the selected summary and messages. Show its `PlatformBadge` in the header, render text bubbles, bind a `TextField` to `model.draft`, and invoke `Task { try await model.sendDraft() }` from the send button. Disable send for blank drafts. Keep the route immutable for the life of the view.

Add `@State private var showsLinkSheet = false` and `@State private var linkError: String?`. When `model.personID(for: route) == nil`, show a **Link to person…** button in the header. Present this exact sheet so linking is always an explicit user action:

```swift
.sheet(isPresented: $showsLinkSheet) {
    LinkPersonSheet(
        people: model.people,
        onSelect: { personID in
            do { try model.linkOpenConversation(to: personID) }
            catch { linkError = error.localizedDescription }
        },
        onCreate: { name in
            do { try model.createPersonAndLinkOpenConversation(displayName: name) }
            catch { linkError = error.localizedDescription }
        }
    )
}
```

Render `linkError` as a small red inline label below the conversation header and clear it whenever the sheet opens.

```swift
public var body: some View {
    VStack(spacing: 0) {
        if let summary = model.inboxItems.flatMap(\.conversationSummaries).first(where: { $0.route == route }) {
            HStack { PlatformBadge(platform: summary.platform); Text(summary.title).fontWeight(.semibold); Spacer() }
                .padding()
            Divider()
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.messagesByRoute[route] ?? []) { message in
                    Text(message.body).padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        Divider()
        HStack {
            TextField("Message…", text: $model.draft).textFieldStyle(.plain)
                .accessibilityIdentifier("message-composer")
            Button { Task { try await model.sendDraft() } } label: { Image(systemName: "arrow.up.circle.fill") }
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message").accessibilityIdentifier("send-message")
        }.padding(12)
    }
    .accessibilityIdentifier("conversation-\(route.accountID)-\(route.conversationID)")
}
```

- [ ] **Step 6: Compose the approved root layout**

Create `RootView.swift`:

```swift
import SwiftUI
import PalloFeatures

public struct RootView: View {
    @Bindable var model: PalloAppModel
    public init(model: PalloAppModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 0) {
            NavigationRailView()
            Divider()
            InboxView(items: model.inboxItems, onSelect: model.selectInboxItem)
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
            Divider()
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder private var detail: some View {
        switch model.detailSelection {
        case .empty: ContentUnavailableView("Choose a conversation", systemImage: "message")
        case let .personSummary(personID):
            ContactSummaryView(
                personName: model.inboxItems.first { $0.id == .person(personID) }?.title ?? "Contact",
                summaries: model.summaries(for: personID),
                onOpen: model.openConversation
            )
        case let .conversation(route): ConversationView(model: model, route: route)
        }
    }
}
```

Delete the no-longer-needed `Sources/PalloUI/Module.swift` target marker.

- [ ] **Step 7: Run UI tests and compile the package**

Run:

```bash
swift test --filter PalloUITests
swift test
swift build
```

Expected: all tests pass and all SwiftUI views compile for macOS 15.

- [ ] **Step 8: Commit the approved interface**

```bash
git add Sources/PalloUI Tests/PalloUITests
git commit -m "feat: build distraction-free Pallo inbox"
```

### Task 7: Add the macOS app and persistent menu-bar lifecycle

**Files:**
- Delete: `Sources/PalloApp/main.swift` if Task 1 created it
- Create: `Sources/PalloApp/PalloApp.swift`
- Create: `Sources/PalloUI/MenuBarContentView.swift`
- Modify: `README.md`
- Test: `Tests/PalloFeaturesTests/PalloAppModelTests.swift`

**Interfaces:**
- Consumes: `InMemoryMessagingGateway`, `Fixtures`, `PalloAppModel`, `RootView`, and `ServiceHealth`.
- Produces: runnable `Pallo` executable with a `WindowGroup` and `MenuBarExtra` sharing one application model.

- [ ] **Step 1: Add failing health-display tests**

Append to `Tests/PalloFeaturesTests/PalloAppModelTests.swift`:

```swift
@MainActor
@Test func healthTitleIsQuietWhenHealthyAndActionableWhenDisconnected() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    #expect(model.health.menuBarTitle == "Pallo is running")
    #expect(ServiceHealth.needsAttention("Reconnect Instagram").menuBarTitle == "Pallo needs attention")
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter healthTitleIsQuietWhenHealthyAndActionableWhenDisconnected`

Expected: compilation fails because `ServiceHealth.menuBarTitle` does not exist.

- [ ] **Step 3: Add presentation-safe health metadata**

Extend `ServiceHealth` in `PalloAppModel.swift`:

```swift
public extension ServiceHealth {
    var menuBarTitle: String {
        switch self {
        case .starting: "Pallo is starting"
        case .healthy: "Pallo is running"
        case .needsAttention: "Pallo needs attention"
        }
    }

    var symbolName: String {
        switch self {
        case .starting: "ellipsis.circle"
        case .healthy: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }
}
```

- [ ] **Step 4: Implement the menu-bar content**

Create `Sources/PalloUI/MenuBarContentView.swift`:

```swift
import AppKit
import SwiftUI
import PalloFeatures

public struct MenuBarContentView: View {
    let health: ServiceHealth
    let openWindow: () -> Void
    public init(health: ServiceHealth, openWindow: @escaping () -> Void) {
        self.health = health; self.openWindow = openWindow
    }

    public var body: some View {
        Text(health.menuBarTitle)
        Divider()
        Button("Open Pallo", action: openWindow)
        Button("Quit Pallo") { NSApplication.shared.terminate(nil) }
    }
}
```

Do not add notification pausing, diagnostics, launch-at-login, or service retry commands in this slice; their menu entries require real service-manager interfaces from later plans.

- [ ] **Step 5: Replace the temporary executable with the SwiftUI app**

Delete `Sources/PalloApp/main.swift` if present and create `Sources/PalloApp/PalloApp.swift`:

```swift
import SwiftUI
import PalloFeatures
import PalloGateway
import PalloUI

@main
struct PalloApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var model = PalloAppModel(
        gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot),
        directory: Fixtures.directory
    )

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: model)
                .task {
                    do { try await model.start() }
                    catch { model.reportStartupFailure(error) }
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContentView(health: model.health) { openWindow(id: "main") }
        } label: {
            Image(systemName: model.health.symbolName)
                .accessibilityLabel(model.health.menuBarTitle)
        }
    }
}
```

Add this exact method to `PalloAppModel` before compiling the app:

```swift
public func reportStartupFailure(_ error: any Error) {
    health = .needsAttention("Pallo could not start: \(error.localizedDescription)")
}
```

- [ ] **Step 6: Build and manually smoke-test persistence after window close**

Run:

```bash
swift test
swift run Pallo
```

Verify manually:

1. The main window shows Maya once and Family separately.
2. Opening Maya shows WhatsApp and Instagram as distinct cards.
3. Opening Instagram and sending a message adds it only to the Instagram timeline.
4. Closing the window leaves the menu-bar icon present.
5. **Open Pallo** restores the main window.
6. **Quit Pallo** removes the menu-bar item and ends the process.

- [ ] **Step 7: Update README and commit the runnable vertical slice**

Add a **Vertical slice behavior** section to `README.md` listing the six smoke-test behaviors above and clearly repeat that the data is fixtures, not real accounts.

```bash
git add README.md Sources/PalloApp Sources/PalloFeatures/PalloAppModel.swift Sources/PalloUI/MenuBarContentView.swift Tests/PalloFeaturesTests/PalloAppModelTests.swift
git commit -m "feat: add persistent Pallo macOS app lifecycle"
```

### Task 8: Harden startup, accessibility, and vertical-slice acceptance

**Files:**
- Modify: `Sources/PalloFeatures/PalloAppModel.swift`
- Modify: `Sources/PalloUI/RootView.swift`
- Modify: `Sources/PalloUI/InboxView.swift`
- Modify: `Sources/PalloUI/ContactSummaryView.swift`
- Modify: `Sources/PalloUI/ConversationView.swift`
- Create: `Tests/PalloFeaturesTests/StartupFailureTests.swift`
- Create: `docs/testing/native-vertical-slice-acceptance.md`

**Interfaces:**
- Consumes: all prior vertical-slice APIs.
- Produces: visible startup failure state, stable accessibility identifiers, and an executable acceptance checklist used by the next Matrix-runtime plan.

- [ ] **Step 1: Write failing startup failure tests**

Create `Tests/PalloFeaturesTests/StartupFailureTests.swift`:

```swift
import Testing
@testable import PalloCore
@testable import PalloGateway
@testable import PalloFeatures

private struct FailingGateway: MessagingGateway {
    struct Failure: Error {}
    func loadSnapshot() async throws -> MessagingSnapshot { throw Failure() }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt { throw Failure() }
}

@MainActor
@Test func startupFailureBecomesVisibleHealthState() async {
    let model = PalloAppModel(gateway: FailingGateway())
    do { try await model.start() } catch { model.reportStartupFailure(error) }
    guard case let .needsAttention(message) = model.health else {
        Issue.record("Expected needs-attention health")
        return
    }
    #expect(message.hasPrefix("Pallo could not start:"))
    #expect(model.healthBannerMessage?.hasPrefix("Pallo could not start:") == true)
}
```

- [ ] **Step 2: Run the test and verify the intended failure or gap**

Run: `swift test --filter StartupFailureTests`

Expected: compilation fails because `PalloAppModel.healthBannerMessage` does not exist.

- [ ] **Step 3: Expose health failures in the root UI and add identifiers**

Add this derived property to `PalloAppModel`:

```swift
public var healthBannerMessage: String? {
    guard case let .needsAttention(message) = health else { return nil }
    return message
}
```

In `RootView`, add a narrow top banner only when `healthBannerMessage` is non-nil. The banner contains the message, uses `accessibilityIdentifier("health-banner")`, and does not cover the inbox.

Add these stable identifiers:

- Inbox root: `pallo-inbox`
- Each inbox row: `inbox-item-<stable ID description>`
- Contact summary root: `contact-summary`
- Each conversation card: `conversation-card-<accountID>-<conversationID>`
- Conversation root: `conversation-<accountID>-<conversationID>`
- Composer: `message-composer`
- Send button: `send-message`

Cover the `InboxItem.ID.accessibilityIdentifier` helper added in Task 6 by appending this test to `AccessibilityModelTests.swift`:

```swift
@Test func inboxAccessibilityIdentifiersAreStable() {
    #expect(InboxItem.ID.person("maya").accessibilityIdentifier == "person-maya")
    let route = ConversationRoute(accountID: "wa", conversationID: "chat")
    #expect(InboxItem.ID.conversation(route).accessibilityIdentifier == "conversation-wa-chat")
}
```

In `RootView`, render a visible health banner above the three-pane `HStack`:

```swift
VStack(spacing: 0) {
    if let message = model.healthBannerMessage {
        Text(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.15))
            .accessibilityIdentifier("health-banner")
    }
    HStack(spacing: 0) {
        NavigationRailView()
        Divider()
        InboxView(items: model.inboxItems, onSelect: model.selectInboxItem)
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
        Divider()
        detail.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Add the acceptance document**

Create `docs/testing/native-vertical-slice-acceptance.md` with:

```markdown
# Native Vertical Slice Acceptance

## Automated

- `swift test` passes.
- `swift build -c release` passes.
- Contact linking is explicit and one-to-one per remote identity.
- Linked inbox aggregation sums unread counts and orders by newest activity.
- Route-safety test proves an Instagram send does not enter the WhatsApp route.
- Every platform badge has an accessible network name.
- Startup failure produces a visible needs-attention state.

## Manual

- Run `swift run Pallo` on Apple silicon/macOS 15+.
- Verify the compact three-pane layout at 900×600 and larger.
- Verify keyboard navigation reaches inbox rows, contact cards, composer, send, and menu-bar actions.
- Verify VoiceOver announces platform names without visible network-name labels.
- Verify Maya opens a contact summary before either network conversation.
- Verify closing the window preserves the menu-bar process and Open Pallo restores it.
- Verify Quit Pallo terminates the process.

## Out of scope for this gate

Synapse, Matrix encryption, bridge provisioning, real accounts, media, launch at login, signed updates, notarization, and uninstallation are covered by later roadmap phases.
```

- [ ] **Step 5: Run final automated verification**

Run:

```bash
swift test
swift build -c release
git diff --check
```

Expected: all tests pass, release build succeeds, and `git diff --check` prints nothing.

- [ ] **Step 6: Run the documented manual acceptance pass**

Run `swift run Pallo`, follow every item in `docs/testing/native-vertical-slice-acceptance.md`, and record the macOS/Xcode versions plus results at the bottom of that file under `## Latest result`. If any item fails, do not mark the task complete; fix the smallest responsible unit and rerun automated plus affected manual checks.

- [ ] **Step 7: Commit vertical-slice hardening**

```bash
git add Sources/PalloFeatures Sources/PalloUI Tests/PalloFeaturesTests docs/testing/native-vertical-slice-acceptance.md
git commit -m "test: harden Pallo vertical slice acceptance"
```

## Completion gate

The plan is complete only when:

- All eight task commits exist in order.
- `swift test` and `swift build -c release` pass on the release-baseline Mac.
- The manual acceptance checklist is recorded and contains no failures.
- The working tree contains no unintended changes.
- The next plan begins with the local Matrix runtime spike and consumes `MessagingGateway` rather than changing UI features to know about Synapse directly.
