# Inbox+ local storage

The encrypted local database for Inbox+. The public entry point is
`package:inboxplus_storage/inboxplus_storage.dart`, and `test/local_store_test.dart` shows how
each method behaves.

```dart
final store = await LocalStore.open(file: databaseFile, key: deviceDatabaseKey);
await store.saveAccount(const AccountRecord(
  id: 'telegram',
  platform: 'telegram',
  displayName: 'Telegram',
));
await store.close();
```

## Using the package

The root `pubspec.yaml` of the consuming app must select SQLite3MultipleCiphers:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

A caller must:

- Pass a random 32-byte key loaded from the platform credential store.
- Report a missing key and keep the database. Never create a replacement key or an empty profile.
- Put the database in its own directory inside the OS application-support directory, never in a
  shared, network or cloud-synced folder.
- Call `resolveSymbolicLinks()` on the support directory before it appends the database directory.
- On Windows, use the current user's private application-support directory.
- Keep attachment files, tokens and connector secrets outside the store.
- Reconcile an interrupted `sending` operation with the connector before it retries.
- Delete the files that `clearDownloadedMediaPaths` returns.
- Record the previous profile directory in the same secure namespace as the key, for
  `rebaseAttachmentPaths`.

## Development

From this directory:

```bash
dart pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test
```

Regenerate `lib/src/local_store.g.dart` after you edit a Drift table.
