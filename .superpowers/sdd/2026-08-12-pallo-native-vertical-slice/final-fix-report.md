# Final Fix Report

## Scope

Implemented the single permitted final-review fix wave on base `1181337` without adding Matrix, real-account, or bridge scope.

1. Conversation sends now use an immutable `DraftSubmission` captured synchronously by the view. It contains the exact `ConversationRoute`, submitted body, and composer revision. Completion clears only that submitted revision, including protection against edit-and-return-to-the-same-text races.
2. `start()` is concurrency-safe and idempotent. Concurrent callers share one startup operation, the model subscribes before loading the snapshot, events are buffered until snapshot application, and startup failure cancels the owned subscription. Explicit `stop()` followed by `start()` creates a fresh working subscription.
3. A strictly newer message event updates the exact matching `RemoteConversation` preview/activity and rebuilds inbox ordering while preserving unread counts. Older messages and delivery-only updates cannot regress the projection.
4. Send failures are observable per conversation. `ConversationView` catches and reports them, renders a stable accessible `send-error-<accountID>-<conversationID>` label, retains the failed draft, exposes retry semantics on the send button, and clears only the matching error after a successful retry.
5. `InboxProjector` rejects a conversation whose referenced identity belongs to another account, preventing malformed graphs from bypassing manual-link boundaries.
6. `ContactDirectoryTests` now directly cover preloaded person dictionary key/ID mismatch and a link whose owner is missing.

## RED Evidence

Each production behavior was exercised before its implementation change.

- `swift test --filter 'inFlightSendKeepsCapturedRouteAndPreservesANewerDraft|sendFailureIsScopedToItsRouteAndSuccessfulRetryClearsIt|sendFailureDescriptorExposesRouteScopedAccessibleState'` exited 1 during compilation because the route/body send API, failure state, and presentation descriptor did not exist.
- `swift test --filter inFlightSendDoesNotClearAReenteredSameTextDraft` exited 1 during compilation because the immutable revision-bearing submission API did not exist.
- `swift test --filter 'concurrentStartCallsShareOneGaplessSubscription|eventPublishedDuringSnapshotLoadIsAppliedAfterTheSnapshot|startupFailureCancelsItsOwnedEventSubscription'` exited 1 with seven issues: no subscription existed before snapshot completion, two snapshot loads occurred, the during-start event was lost, and failure did not own a subscription to cancel.
- `swift test --filter 'newerOutgoingMessageRefreshesOnlyItsConversationAndReordersInbox|olderMessageAndDeliveryUpdateDoNotRegressConversationProjection'` exited 1 with eight issues: conversation preview/activity and inbox ordering remained at snapshot values.
- `swift test --filter 'crossAccountIdentityReferenceCannotAggregateIntoALinkedPerson|initialDirectoryRejectsPersonDictionaryKeyAndIDMismatch|initialDirectoryRejectsLinkWhoseOwnerIsMissing'` exited 1 because the malformed cross-account conversation was aggregated, producing two summaries and unread count 10. The two directory tests passed immediately because their guards already existed; they close the requested direct-test gap rather than claim new behavior.
- Mutation check for the Minor gap: temporarily removing the person key/ID and link-owner guards made both new directory tests fail because no error was thrown. Restoring the existing guards made both pass.

## GREEN Evidence

Focused runs after each minimal implementation change:

- Route capture, newer-draft preservation, same-text revision preservation, failure/retry state, and accessibility descriptor: 5 tests passed.
- Concurrent/gapless startup, failure cleanup, repeated start, stop, restart, and startup-failure presentation: 7 tests passed.
- Message projection/upsert behavior: 3 tests passed.
- Inbox projector and contact-directory boundaries: 12 tests passed.
- Restored Minor-gap invariant checks: 2 tests passed.

Fresh final verification after all source, test, UI, and acceptance-document changes:

```text
swift test
  PASS — 47 tests, 0 failures

swift build -c release -Xswiftc -warnings-as-errors
  PASS — production build completed with no warnings

git diff --check
  PASS — no output

pgrep -x Pallo
  PASS — no Pallo process running
```

## Files Changed

- `Sources/PalloFeatures/PalloAppModel.swift`
- `Sources/PalloFeatures/InboxProjector.swift`
- `Sources/PalloUI/ConversationView.swift`
- `Tests/PalloFeaturesTests/PalloAppModelTests.swift`
- `Tests/PalloFeaturesTests/InboxProjectorTests.swift`
- `Tests/PalloFeaturesTests/ContactDirectoryTests.swift`
- `Tests/PalloUITests/AccessibilityModelTests.swift`
- `docs/testing/native-vertical-slice-acceptance.md`

## Commits

- `7a16461 fix: harden Pallo event and send state`

## Residual Concerns

No residual automated code concern is known within this final-review scope. The six live-UI checks already recorded as environment-caused `UNVERIFIED` in the acceptance document still require a bundled app or human-accessible macOS UI session before release; this wave did not broaden or alter that previously accepted limitation.

## Authorized Residual Fix Cycle

### Scope

Implemented the two explicitly authorized residual Important fixes on base `a264ff2`.

1. Every captured `DraftSubmission` now carries a monotonic generation scoped to its exact route. Successful sends clear route failure state and the matching draft only when their generation remains current. `reportSendFailure` accepts the complete submission and ignores stale failures by the same rule. The UI passes the immutable submission through both success and failure paths.
2. Startup now has one model-owned task plus cancellation-aware, identity-keyed caller waiters. Canceling one waiting caller completes that caller with `CancellationError` without affecting the shared leader. `stop()` cancels the owned startup task, buffered event subscription, and every relevant caller; a later start creates one fresh gapless subscription. A synchronized cancellation flag and dictionary removal ensure operation completion and cancellation cannot double-resume or leak a continuation.

### RED Evidence

- Added `olderSuccessCannotClearANewerFailureOrDraftOnTheSameRoute` and `olderFailureCannotReplaceANewerSuccessOnTheSameRoute`, then ran their focused filter. The command exited 1 during compilation because `reportSendFailure` still accepted only `ConversationRoute`; the compiler reported that `DraftSubmission` could not be converted to `ConversationRoute`. This established the missing submission identity at the failure boundary before production changes.
- Added a cooperative delayed snapshot gateway plus `cancellingAConcurrentStartCallerDoesNotCancelTheSharedLeader`, `stopCancelsSuspendedStartupAndAllStartCallersPromptly`, and `restartAfterCancelledStartupOwnsOneGaplessSubscription`. Their focused run compiled and exited 1 with five intended issues: the canceled waiter did not complete promptly, stop did not promptly finish all callers, the snapshot load was not canceled, the stopped leader did not finish promptly, and restart retained the uncanceled prior load instead of one clean gapless subscription.

### GREEN Evidence

- Send ordering focused run: 6 tests passed, covering both completion inversions plus prior route, newer-draft, same-text-revision, retry, and accessible failure behavior.
- Startup lifecycle focused run: 8 tests passed, covering isolated caller cancellation, stop cancellation, clean restart, concurrent idempotence, gapless buffering, startup-failure cleanup, repeated start, and stop/restart semantics.
- `swift test --filter PalloAppModelTests`: 28 tests passed.
- `swift test --filter PalloUITests`: 5 tests passed.
- Pre-commit full verification: `swift test` passed 52 tests with 0 failures; `swift build -c release -Xswiftc -warnings-as-errors` completed without warnings; `git diff --check` emitted no output; and no Pallo process was running.

### Files Changed

- `Sources/PalloFeatures/PalloAppModel.swift`
- `Sources/PalloUI/ConversationView.swift`
- `Tests/PalloFeaturesTests/PalloAppModelTests.swift`
- `docs/testing/native-vertical-slice-acceptance.md`
- `.superpowers/sdd/2026-08-12-pallo-native-vertical-slice/final-fix-report.md`

### Commit

- `a62e953 fix: order sends and cancel startup safely`

### Residual Concerns

No residual automated concern is known in this additional scoped cycle. The same six previously documented live-UI checks remain environment-caused `UNVERIFIED`; this cycle did not change their manual execution requirements or introduce any real-account/Matrix scope.
