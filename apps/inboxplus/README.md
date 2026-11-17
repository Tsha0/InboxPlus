# Inbox+ Flutter application

The shared interface and application code for Android, iOS, macOS, Windows and Linux.

From this directory:

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d macos
```

- Pick a target that the current host supports.
- The native runners compile `../../native/connectors` with the pinned Go toolchain, so Flutter
  alone cannot build the app. See the [README requirements](../../README.md#requirements).
- Tests use fakes and isolated storage. They never sign in to a real messaging account.
- Checks, packaging and releases are in [CONTRIBUTING](../../CONTRIBUTING.md).
