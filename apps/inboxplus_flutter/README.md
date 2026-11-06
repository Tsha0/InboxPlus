# Inbox+ Flutter application

Shared interface and application code for Android, iOS, macOS, Windows and Linux. Each device
uses its own encrypted SQLite store and embedded Go connectors; no Mac or shared server is needed.

See the repository [README](../../README.md#build-from-source) for toolchains, build commands,
network limitations and migration status, and [CONTRIBUTING](../../CONTRIBUTING.md) for checks.

From this directory:

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d macos
```

Choose a target supported by the current host. Native runners compile `../../native/connectors`
with Go 1.27.3, so an ordinary Flutter-only installation is insufficient for an application build.
Tests use fakes and isolated storage; they do not authenticate a real messaging account.
