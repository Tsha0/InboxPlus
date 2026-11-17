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

## Caller responsibilities

`test/local_store_test.dart` documents the store's behavior. A caller must also:

- Reconcile an interrupted `sending` operation with the connector before it retries. Storage never
  resends.
- Delete the files that `clearDownloadedMediaPaths` returns. The store never deletes a file.
- Record the previous profile directory in the same secure namespace as the key, so that
  `rebaseAttachmentPaths` can move references after an OS restore.

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
