# Inbox+ local storage

This pure Dart package stores application-owned data in an encrypted, per-device
SQLite database. It is usable from Flutter on Android, iOS, macOS, Windows and
Linux without a host computer. It does not synchronize devices or connect to
messaging networks.

The public entry point is `package:inboxplus_storage/inboxplus_storage.dart`.

```dart
final store = await LocalStore.open(file: databaseFile, key: deviceDatabaseKey);
await store.saveAccount(const AccountRecord(
  id: 'telegram',
  platform: 'telegram',
  displayName: 'Telegram',
));
await store.close();
```

## Encryption and file ownership

The caller supplies a cryptographically random, 32-byte key loaded from the
platform credential store. This package never saves that key. If a database
exists and its key is unavailable, the caller must report the failure and keep
the database; it must not generate a replacement key or empty profile.

The pinned `sqlite3` build hook bundles SQLite3MultipleCiphers and verifies its
published artifact hash. Connections explicitly select ChaCha20 encryption and
verify cipher support before using the key. A consuming Flutter application's
root `pubspec.yaml` must also select this library:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

An ordinary SQLite build is rejected. Existing plaintext, corrupt, foreign and
newer-schema databases are rejected instead of being replaced or adopted.
Existing database validation opens read-only before Drift performs any schema
work. Public failures expose fixed error codes rather than SQL statements,
bindings, message bodies, credentials or file paths.

Use a dedicated database directory inside the operating system's application
support directory. Resolve the platform-provided support directory with
`resolveSymbolicLinks()` before appending the dedicated directory; Apple
platforms can return paths containing system aliases such as `/var`. Database
files, ancestors and SQLite sidecars must not be symbolic links. On POSIX, this
package sets the dedicated database directory to `0700` and the database and
existing sidecars to `0600`. On Windows, the caller must use the current user's
private application-support directory with its inherited ACLs. Do not place
databases in shared, network or cloud-synchronized folders.

The store owns database rows only. Attachment bytes belong in separate private
files managed by the application. `AttachmentRecord.localPath` is metadata, not
permission to read or delete that path. Removing accounts or clearing drafts
never deletes caller-owned files. Authentication tokens and connector session
secrets belong in the platform credential store or connector-owned store.

## Data and send behavior

- Accounts, conversations and messages use account-scoped conversation routes.
  Identical network IDs in different accounts cannot overwrite one another.
- Recent messages are returned chronologically with a default window of 50.
- Conversation send availability persists with its explanation, so an unsupported
  encrypted thread remains unavailable after reopening the app.
- `loadMessage` looks up an account-scoped message directly, including records
  outside the recent window, so repeated events and old edits remain distinct.
- `loadStorageSummary` counts every retained message and its attachment metadata,
  including messages outside the recent window. Actual cached byte counts belong
  to the application's private media directory.
- `clearDownloadedMediaPaths` atomically clears downloadable cache paths across
  all messages and returns the files the caller may delete. It requires a
  canonical private media directory, rejects symlinks and paths outside it, and
  preserves files referenced by drafts, pending sends or non-downloadable media.
  It never deletes files itself. Link and download availability metadata survive
  reopening the profile.
- `rebaseAttachmentPaths` updates private media and staging references after an
  operating-system restore moves the profile directory. It changes messages,
  drafts and pending sends together, preserves payloads and revisions, rejects
  symbolic links, and leaves external paths and file bytes untouched. The caller
  records the previous profile directory in the same secure namespace as its key.
- Draft updates increment a durable revision. `clearDraft` clears only the
  supplied revision and preserves monotonic revisions after clearing.
- `enqueueDraft` captures an immutable draft payload under a caller-supplied
  command ID. Repeating the same command ID returns the existing pending send.
- `completeSend` atomically records the acknowledged message and removes its
  pending send. It clears the draft only when no newer revision exists.
- Failed or uncertain pending sends remain durable. The application must
  reconcile an interrupted `sending` operation with the connector before
  retrying; storage does not resend anything automatically.
- `resolvePendingSend` removes a command after explicit user resolution. It can
  clear only the captured draft revision, preserves newer edits, and creates no
  acknowledged message.
- Contact changes are transactional. An account-scoped remote identity can link
  to only one person. Removing an account removes its links while keeping people
  and other accounts intact.
- Favorites, unread overrides, mute expiry and hide thresholds persist even if a
  conversation has not yet been loaded into the local cache.
- `importLegacy` commits imported accounts, contacts and preferences together.
  A failed import rolls back every change, and successful imports can be retried
  before publishing the profile to the interface.

Timestamps use UTC microseconds since the Unix epoch. This package does not open
or migrate the existing Swift application's profile, JSON stores, Matrix SDK
database, Keychain entries or runtime. An explicit importer must convert
Swift Codable dates from their 2001 epoch and retain source data on failure.

## Development

From this directory:

```bash
dart pub get
dart run build_runner build
dart analyze
dart test
```

Direct dependencies are pinned exactly and `pubspec.lock` is committed with the
package. Regenerate `lib/src/local_store.g.dart` after editing Drift tables.
The tests use disposable encrypted databases and fake application records; they
do not sign into networks or touch installed Inbox+ profiles.
