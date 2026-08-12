# Pallo macOS Design

Status: Approved in collaborative design review on 2026-08-12  
License: AGPL-3.0-or-later  
Initial platform: macOS desktop, direct download  

The initial engineering and release baseline is Apple silicon running macOS 15 or later. Intel support is outside Pallo 1.0. Each release publishes its exact supported macOS versions, and adapter capabilities that vary by OS version are tested and disclosed.

## Summary

Pallo is a local-first, open-source universal inbox for one person connecting personal messaging accounts. It uses Matrix as its canonical event and synchronization layer and open-source Matrix bridges to connect external services. Pallo manages the Matrix homeserver, bridges, credentials, updates, and recovery behind a native, distraction-free macOS interface.

Pallo is conversation-focused. It does not include social feeds, posts, stories, status publishing, or voice and video calls. It renders message attachments—including photos, files, stickers, audio, and video—when bridges provide them. Supported audio and video play inline. Proprietary content such as Instagram Reels, TikTok posts, Stories, and view-once media opens in its original application through a verified deep link.

Pallo has no operated cloud in this design. The application, local Matrix server, bridge processes, credentials, message database, and media cache remain on the user's Mac.

## Product goals

- Present personal conversations from supported services in one quiet inbox.
- Make infrastructure invisible: users connect accounts, not homeservers or bridge bots.
- Keep message processing and stored history on the user's Mac.
- Continue receiving messages and notifications after the main window closes.
- Let users manually link multiple network identities to one Pallo person.
- Preserve each remote conversation as a separate, explicitly selected send route.
- Render bridge-supported content faithfully and never silently omit unknown content.
- Support the complete target network roster through a common adapter contract and certification suite.
- Distribute a signed, notarized, open-source macOS application directly from Pallo's website.

## Non-goals

- Social feeds, posts, Stories, status publishing, or content discovery
- Voice or video calls
- Multiple accounts from the same platform
- Automatic or suggested contact matching
- Shared team inboxes and business-agent workflows
- A Pallo-operated account, synchronization cloud, backup service, or telemetry pipeline
- Mobile, Windows, or Linux clients in the initial design
- Exposing general Matrix rooms, federation, administration, or bridge-bot interfaces
- WeChat support until a viable, maintained personal-account bridge exists

## Experience design

### Main window

Pallo uses the approved compact three-pane layout:

1. A narrow navigation rail contains the Pallo mark, inbox, search, contacts, and settings.
2. The inbox lists people or standalone conversations, latest-message previews, timestamps, and unread state.
3. The detail pane shows either a conversation or a linked person's contact summary.

Network names do not clutter the inbox. A small, accessible platform icon appears beside each conversation and in the open-conversation header. Every icon has a VoiceOver label and tooltip so network identity is not conveyed through color or shape alone.

The interface contains no feed, engagement counters, suggested content, advertisements, or unrelated discovery surfaces.

### Background behavior

Closing the main window leaves Pallo running. A small macOS menu-bar item shows overall connection health and offers these actions:

- Open Pallo
- View accounts needing attention
- Pause or resume notifications
- Retry disconnected accounts
- Open diagnostics
- Quit Pallo

Choosing Quit stops the app and all Pallo-managed background services cleanly. Launch at login is enabled only with the user's consent and can be disabled in settings.

### Account management

Pallo permits one connected account per user-facing service. Instagram and Facebook Messenger count as separate services even when one underlying Meta bridge implements both. The account screen shows platform icon, connection state, last successful synchronization, and any required action. It does not show Matrix room IDs, bridge bots, raw logs, or configuration files in normal operation.

Disconnecting an account stops future synchronization but preserves local history by default. A separate destructive action removes that account's local history and credentials after explicit confirmation.

## Manual contact linking

Pallo never automatically merges or suggests that two identities are the same person.

### Domain model

- **PalloPerson**: local-only user-created identity with a display name and optional local avatar.
- **RemoteIdentity**: an identity supplied by one platform account, keyed by adapter, connected account, and stable remote identifier.
- **RemoteConversation**: a distinct conversation with its own Matrix room, remote identifiers, capabilities, unread state, and send route.
- **PersonLink**: explicit local relationship from a `PalloPerson` to one or more `RemoteIdentity` records.

Linking identities changes only Pallo's presentation. It never combines remote rooms, rewrites messages, changes remote contacts, or moves history between services.

### Linking interaction

From a conversation, the user chooses **Link to person…**, then selects an existing Pallo person or creates one, reviews the exact source identity, and confirms. Unlinking removes only `PersonLink`.

### Linked-person interaction

A linked person appears once in the inbox. Its position is determined by the newest activity among its remote conversations, and its unread badge is the sum of their unread counts.

Opening a linked person displays the approved contact-summary view. Each remote conversation appears as a separate card with its platform icon, latest preview, timestamp, and unread state. Selecting a card opens that exact remote conversation.

The composer is permanently bound to the open `RemoteConversation`. Pallo does not automatically switch the outgoing platform. This avoids accidental cross-network sends.

## System architecture

### Pallo macOS app

A native SwiftUI application provides the main window, menu-bar interface, onboarding, account management, contacts, search, conversation rendering, media playback, settings, and diagnostics.

The app integrates the Apache-2.0 Matrix Rust SDK through its Swift bindings. The SDK handles Matrix authentication, synchronization, encrypted event processing, room state, local client caching, and timeline primitives. Pallo builds its own focused domain and presentation layer rather than forking a general Matrix client.

### Local Synapse homeserver

Synapse is Pallo's private local Matrix homeserver. It stores canonical rooms and events, accepts bridge application-service traffic, and synchronizes the Pallo client. Users never interact with Synapse directly.

Synapse has these constraints:

- Bind client, application-service, provisioning, and administration listeners to loopback interfaces only.
- Disable federation, public registration, public room directories, guest access, and remote administration.
- Create exactly the internal users and application services required by Pallo.
- Use encrypted bridge rooms where supported.
- Store data beneath Pallo's user-scoped Application Support directory.

The initial engineering spike may use Synapse with SQLite because Pallo is a single-user, non-federated deployment. SQLite is retained for public releases only if migration, recovery, and representative-load tests pass. The representative load is at least 100,000 messages, 2,000 conversations, concurrent history import from three bridges, live incoming traffic, search, and media metadata updates without event loss. On the release-baseline Mac, a warm cached timeline must open within 500 ms at the 95th percentile, a committed local event must appear in the UI within 2 seconds at the 95th percentile, and background import must not block typing or scrolling for more than one animation frame. If SQLite fails any requirement, Pallo bundles and manages PostgreSQL before public release. This is a Pallo-specific decision; standard Synapse guidance recommends PostgreSQL for conventional production servers.

### Bridge adapters

Each external service runs as an isolated adapter process. Existing `mautrix` or Beeper bridge code is reused where its license and supported configuration permit. Pallo adds a thin adapter-management layer rather than modifying every bridge into application code.

Each adapter owns:

- Its bridge binary and version
- A dedicated configuration and data directory
- Its network-specific login and provisioning flow
- Capability discovery
- Health state and structured, redacted diagnostics
- Remote deep-link generation

The Pallo UI never communicates directly with WhatsApp, Instagram, or another remote service. It reads and writes Matrix events. The service manager communicates with adapters only for provisioning, health, lifecycle, and capabilities.

Each adapter receives only its own secrets and filesystem permissions. A bridge crash cannot directly stop another bridge.

### iMessage adapter

iMessage uses a separate macOS adapter backed by the signed-in Messages application and permitted local macOS databases, automation, and accessibility APIs. Pallo requests only the permissions required by the implemented feature set and explains why each permission is needed.

The iMessage adapter is Mac-only and does not claim to be an official public iMessage API. It must preserve normal macOS security settings and must not require disabling System Integrity Protection.

### External Matrix account adapter

Pallo's internal Synapse remains non-federated. If the user connects an external Matrix account, a dedicated adapter logs into that remote homeserver as a client and translates its selected conversations into local rooms. Pallo does not enable federation on its local homeserver to implement this feature.

### Service manager

A Pallo-owned background service manager supervises Synapse and every configured adapter. It runs in the user's session through supported macOS launch-at-login mechanisms and does not require root privileges.

Responsibilities include:

- Install versioned service bundles
- Generate internal configuration and application-service registrations
- Start dependencies in order and wait for readiness
- Monitor component health
- Restart failed components with bounded exponential backoff
- Stop repeated crash loops and request user action
- Coordinate backups, database migrations, updates, rollback, and removal
- Expose a narrow authenticated local control interface to the Pallo app

Pallo does not require users to install Docker, Homebrew, Python, Go, Rust, PostgreSQL, or developer tools. Public artifacts contain all required signed runtime components.

## Message data flow

### Incoming message

1. A network adapter receives an event through the remote service's supported client session.
2. The adapter converts the event into a Matrix event with stable remote identifiers and source metadata.
3. Synapse commits the event to the relevant local room.
4. Matrix Rust SDK synchronizes and decrypts the event.
5. Pallo maps it into its conversation presentation model and updates unread state, notifications, and linked-person ordering.

Duplicate remote identifiers are idempotent. Out-of-order events are ordered by remote timestamp plus stable tie-breaking metadata without changing their original identifiers.

### Outgoing message

1. The user composes within an explicitly selected `RemoteConversation`.
2. Pallo validates the content against that adapter's current capability set.
3. Pallo creates a local pending event associated with that exact route.
4. Synapse delivers it to the correct bridge application service.
5. The adapter sends it to the remote network and reports acknowledgement or failure.
6. Pallo updates the exact message to sent, delivered, read, or failed only when that state is supported and observed.

Pallo never displays a successful send state before bridge acknowledgement.

## Message and media contract

Pallo renders these event categories natively when the bridge supplies a usable representation:

- Plain and formatted text
- Emoji
- Replies and quoted context
- Edits and deletions
- Reactions
- Photos and image galleries
- GIFs and stickers
- Ordinary files
- Audio and voice messages
- Video
- Link previews

Audio and video use user-initiated inline playback with play, pause, seek, duration, and volume controls. Pallo does not autoplay conversation media.

Remote media downloads lazily. Cached media retains its source adapter, remote message identifier, content type, size, and deep link. Cache cleanup may remove reproducible media files, but never message records or irreplaceable local content without explicit consent.

App-native content uses a preview card and an **Open in app** action. Examples include Reels, TikTok posts, Stories, view-once media, and proprietary interactive messages. Pallo does not imitate view-once or disappearing-content semantics. If no preview is available, the card explains what the bridge reported.

Unknown Matrix event types and bridge failures always produce a visible fallback event. Pallo does not silently drop a message.

Compose controls are capability-driven. Unsupported actions are absent or disabled for that conversation rather than attempted optimistically.

## Network compatibility contract

Pallo 1.0 targets this complete roster:

- WhatsApp
- Instagram DMs
- Facebook Messenger
- Telegram
- Signal
- Discord
- Slack
- X direct messages
- LinkedIn messaging
- Google Messages, including supported SMS/RCS behavior
- Google Chat
- Google Voice
- iMessage on macOS
- External Matrix accounts
- IRC
- Bluesky chat

Pre-1.0 builds may expose a certified subset while integration work continues. Pallo 1.0 does not ship until every listed adapter passes the release's compatibility suite, or the roster is changed through an explicit design revision. Experimental adapters are opt-in and clearly labelled.

Repository availability is not proof of product support. Every adapter must provide or explicitly declare:

- Connect, disconnect, and reconnect
- Conversation discovery and history synchronization
- Live incoming and outgoing messages
- Accurate acknowledgement and failure state where the remote platform exposes it
- Platform icon, remote deep links, and health state
- Supported incoming content types
- Supported compose actions and size limits
- Clean removal and preservation/erasure behavior

## Onboarding and lifecycle

### First run

1. Explain Pallo's purpose and local-only privacy model.
2. Install and verify the local service bundle.
3. Create the internal Synapse identity and application services.
4. Request notifications, launch-at-login, and iMessage-specific permissions only when needed.
5. Offer account connection cards.

Account login uses each adapter's provisioning interface and is presented natively by Pallo. QR codes, phone verification, OAuth, passwords, or device approval appear as required by the platform. Raw bridge-bot conversations remain hidden.

### Updates

Pallo checks for signed update metadata without sending account or message information. Download and installation require user approval in the initial release.

Updates follow this sequence:

1. Download app and service artifacts.
2. Verify manifest and artifact signatures.
3. Back up affected configuration and databases.
4. Stop affected services in dependency order.
5. Atomically switch versioned artifacts.
6. Run migrations and health checks.
7. Commit the new version only after verification.
8. Roll back binaries, configuration, and databases together if verification fails.

Pallo never repairs an update by silently deleting message history.

## Failure and recovery

- **Network offline:** cached history and drafts remain available. The account shows a quiet reconnecting state and retries with bounded exponential backoff.
- **Authentication expired:** outgoing sends stop for that account. History remains available. Pallo notifies once and provides an explicit reconnect flow.
- **Send failure:** the exact message remains visibly unsent with retry controls. Automatic retry is limited to errors known to be transient and cannot duplicate an acknowledged remote message.
- **Bridge crash:** restart only that process. After the configured crash limit, stop retrying and surface diagnostics.
- **Synapse unavailable:** stop outgoing work, enter a clearly marked degraded/read-only state where cached SDK data permits it, and attempt verified repair or backup restoration.
- **Low disk space:** stop optional media downloads first and warn the user. Never automatically delete messages.
- **Update failure:** restore the complete pre-update service and data state, then report what failed.
- **Unknown event or malformed adapter output:** isolate the event, render an unavailable-content placeholder, and retain redacted diagnostics.

Visibility escalates from a menu-bar health dot, to quiet inline state, to an account banner when action is required, to a macOS notification only for prolonged or blocking problems.

## Privacy and security

### Trust boundary

Pallo is an endpoint for every connected encrypted service. Bridges must access plaintext to translate messages. Matrix encryption protects local Matrix traffic and storage where configured, but Pallo does not claim uninterrupted end-to-end encryption across two different networks.

### Secrets and local data

- Store root application secrets, Matrix client credentials, update keys, and bridge secrets suitable for Keychain storage in macOS Keychain.
- Some bridge sessions necessarily live in bridge databases. Keep each database in a user-only directory, never place tokens in logs or process arguments, and rely on FileVault for full-volume protection when enabled.
- Protect the Matrix SDK's local store with its supported store encryption, with the store key held in Keychain.
- Use restrictive filesystem permissions for Synapse, adapter, backup, log, and media directories.
- Bind all Pallo control and Matrix endpoints to loopback interfaces and authenticate even local control requests.
- Redact message bodies, access tokens, contact identifiers, attachment URLs, cookies, and verification codes from logs.

### Privacy defaults

- No Pallo cloud account, backup, analytics, or tracking
- Crash reports and diagnostic sharing are opt-in
- Diagnostic exports omit conversation content by default
- Notifications can hide sender and message preview on the lock screen
- External link-preview fetching can be disabled
- No third-party analytics SDKs in the application or service manager

### User controls

Users can disconnect accounts, erase one account's local history, erase all Pallo data, disable launch at login, stop every service, inspect component versions and licenses, and export redacted diagnostics. Destructive actions identify their exact scope and require confirmation.

### Release security

The application and bundled service artifacts are signed and notarized. Update manifests and artifacts are signature-verified. Builds use dependency lockfiles, produce a software bill of materials, run vulnerability scans, and avoid privileged helpers unless a separately reviewed macOS requirement makes one unavoidable.

## Testing and release gates

### Unit and UI-state tests

- Inbox sorting and unread aggregation
- Manual linking, unlinking, and deletion boundaries
- Reply routing cannot cross `RemoteConversation` records
- Message-state transitions and draft preservation
- Rendering for every known and unknown event category
- Capability-driven compose controls
- Menu-bar and account-health state derivation
- Secret redaction

### Contract tests

A deterministic dummy bridge exercises the same Matrix application-service and provisioning contracts as real adapters. Contract fixtures cover login steps, history backfill, live events, duplicate/out-of-order events, acknowledgements, edits, reactions, deletions, media, capability changes, auth expiry, deep links, and malformed input.

### Local-stack integration tests

Tests launch isolated Synapse, service manager, dummy adapters, and Pallo client state. They verify clean startup, shutdown, restart, migration, backup, rollback, service crash isolation, low-disk behavior, and upgrade from every supported previous data version.

### End-to-end macOS tests

Automated UI tests cover first run, permission explanations, account provisioning with mocks, background operation after closing the window, menu-bar actions, contact linking, contact-summary routing, inline media, accessibility, disconnect, erasure, and uninstallation.

### Live-network adapter certification

Each adapter passes a controlled black-box suite against its live service using dedicated test accounts:

- Fresh login and logout
- History import
- Incoming and outgoing text
- Every declared supported media type
- Replies, edits, reactions, deletion, and read state where declared
- Offline recovery and auth expiry
- Deep links
- Account removal

Capability differences are recorded as expected adapter results rather than concealed failures.

### Failure injection

Tests interrupt the network during sends and media downloads, crash adapters, delay or stop Synapse, expire authentication during synchronization, fill disk space during migration, terminate the app during update, and inject duplicate, reordered, or malformed events.

### Release acceptance

A supported clean Mac without developer tools must be able to install Pallo, complete local setup, connect a certified account, send and receive after the main window closes, survive reboot, update and roll back without losing history, and remove its background services during uninstall.

Accessibility acceptance includes complete keyboard operation, meaningful VoiceOver labels, sufficient contrast, reduced-motion behavior, and scalable text without clipped primary actions.

Pallo provides an explicit **Settings → Uninstall Pallo** flow and a signed standalone uninstaller for cases where the main app cannot launch. Uninstallation stops and unloads the launch agent, removes managed binaries and configuration, and separately asks whether local messages, media, and credentials should also be erased. Moving the application bundle to Trash alone cannot guarantee background-service cleanup, so the website and app explain the supported removal flow.

## Open-source and distribution policy

Pallo's source is licensed under AGPL-3.0-or-later. Third-party components retain their original licenses and notices. The project maintains a machine-readable dependency inventory and a human-readable license screen.

The website distributes signed and notarized application packages and publishes checksums, release notes, supported macOS versions, certified adapter versions, known limitations, source tags, and reproducible build instructions where feasible.

The first implementation phase includes a license and redistribution audit for every bundled bridge and runtime. A component that cannot legally or safely be redistributed must be built from source under a compliant process, installed separately with explicit user guidance, replaced, or removed through an explicit design revision.

## Authoritative technical references

- [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk)
- [Synapse installation documentation](https://matrix-org.github.io/synapse/latest/setup/installation.html)
- [mautrix repositories](https://github.com/mautrix)
- [Beeper open-source bridge inventory](https://developers.beeper.com/open-source)
- [Beeper self-hosted bridge mapping](https://developers.beeper.com/bridges/self-hosting)
- [Beeper platform-iMessage library](https://github.com/beeper/platform-imessage)
