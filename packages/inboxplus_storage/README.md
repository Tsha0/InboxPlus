# Inbox+ local storage

This pure Dart package keeps application-owned data in an encrypted SQLite database on each
device. It works from Flutter on Android, iOS, macOS, Windows and Linux. It does not sync devices
or connect to messaging networks.

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

## Encryption

- The caller supplies a random 32-byte key from the platform credential store. The package never
  saves the key.
- If a database exists and its key is unavailable, report the failure and keep the database. Never
  generate a replacement key or an empty profile.
- The pinned `sqlite3` build hook bundles SQLite3MultipleCiphers and verifies its published
  artifact hash. Each connection selects ChaCha20 and verifies cipher support before it uses the
  key.
- The store rejects an ordinary SQLite build, and rejects a plaintext, corrupt, foreign or
  newer-schema database. It never replaces or adopts one.
- The store validates an existing database read-only before Drift does any schema work.
- Public failures carry fixed error codes. They never include SQL, bindings, message bodies,
  credentials or file paths.

The root `pubspec.yaml` of a consuming Flutter application must select the same library:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

## Files

- Use a dedicated database directory inside the OS application-support directory. Never use a
  shared, network or cloud-synced folder.
- Call `resolveSymbolicLinks()` on the support directory before you append the database directory.
  Apple platforms can return a path through a system alias such as `/var`.
- The database files, their ancestors and the SQLite sidecars must not be symbolic links.
- On POSIX, the package sets the database directory to `0700` and the database and existing
  sidecars to `0600`. On Windows, use the current user's private application-support directory
  with its inherited ACLs.
- The store owns database rows only. Attachment bytes live in private files that the application
  manages. `AttachmentRecord.localPath` is metadata, not permission to read or delete that path.
- Removing an account or clearing a draft never deletes a caller-owned file.
- Authentication tokens and connector session secrets belong in the platform credential store or
  a connector-owned store, not here.

## Behavior

Messages:

- Accounts, conversations and messages use account-scoped conversation routes. The same network
  ID in two accounts cannot overwrite the other.
- Recent messages return in chronological order, 50 by default.
- `loadMessage` finds one account-scoped message, including one outside the recent window. Repeated
  events and old edits stay distinct.
- `loadStorageSummary` counts every retained message and its attachment metadata. Cached byte
  counts belong to the application's private media directory.
- A conversation's send availability persists with its explanation. An unsupported encrypted
  thread stays unavailable after the app reopens.
- Timestamps are UTC microseconds since the Unix epoch.

Drafts and sends:

- Each draft update increments a durable revision. `clearDraft` clears only the revision you pass,
  and revisions keep increasing after a clear.
- `enqueueDraft` captures an immutable draft payload under a command ID from the caller. The same
  command ID returns the existing pending send.
- `completeSend` records the acknowledged message and removes its pending send in one transaction.
  It clears the draft only when no newer revision exists.
- A failed or uncertain pending send stays durable. Storage never resends. The application must
  reconcile an interrupted `sending` operation with the connector before it retries.
- `resolvePendingSend` removes a command after the user resolves it. It can clear only the captured
  draft revision, keeps newer edits and creates no acknowledged message.

Media paths:

- `clearDownloadedMediaPaths` clears downloadable cache paths across all messages in one
  transaction and returns the files that the caller may delete. It never deletes a file itself.
- It requires a canonical private media directory, and rejects symlinks and paths outside that
  directory. It keeps files that a draft, a pending send or non-downloadable media still uses.
- Link and download availability metadata survive a reopen.
- `rebaseAttachmentPaths` updates private media and staging references after an OS restore moves
  the profile directory. It changes messages, drafts and pending sends together, and keeps
  payloads and revisions. It rejects symbolic links and leaves external paths and file bytes alone.
- The caller records the previous profile directory in the same secure namespace as its key.

Contacts and preferences:

- Contact changes are transactional. An account-scoped remote identity links to only one person.
- Removing an account removes its links and keeps the people and the other accounts.
- Favorites, unread overrides, mute expiry and hide thresholds persist even for a conversation
  that is not in the local cache yet.

Legacy import:

- `importLegacy` commits imported accounts, contacts and preferences together. A failed import
  rolls back every change. A successful import can be retried before the interface sees the
  profile.
- The package does not open or migrate the earlier Swift application's profile, JSON stores,
  database, Keychain entries or runtime. An importer converts those first.
- An importer must convert Swift Codable dates from their 2001 epoch and keep the source data on
  failure.

## Development

From this directory:

```bash
dart pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test
```

- Direct dependencies are pinned exactly and `pubspec.lock` is committed.
- Regenerate `lib/src/local_store.g.dart` after you edit a Drift table.
- Tests use disposable encrypted databases and fake records. They never sign in to a network or
  touch an installed Inbox+ profile.
