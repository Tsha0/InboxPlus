# Mimo

<p align="center">
  <img src="docs/assets/mimo-mascot.png" alt="Mimo, the app's blue puppy mascot" width="320">
</p>

Mimo is a local-first messaging inbox for macOS. This is a development build.

## Requirements

- Apple silicon Mac with macOS 15 or later
- Swift 6.2 or newer
- Homebrew CPython 3.12
- `cmake` (`brew install cmake`)

## Install

```bash
Scripts/build-app.sh --install
/Applications/Mimo.app/Contents/MacOS/MimoRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
```

Open `/Applications/Mimo.app`. With one prepared profile, the app attaches automatically.
With several profiles, launch it with `MIMO_PROFILE=<name>`.

The default build is ad-hoc signed. Set `MIMO_SIGNING_IDENTITY` to use a certificate.
For release packaging, see the required environment variables in
[`Scripts/package-release.sh`](Scripts/package-release.sh).

### iMessage permissions

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Add `/Applications/Mimo.app`.
3. Quit and reopen Mimo.

Allow Automation control of Messages when prompted on the first send.

## Development

```bash
swift build
swift test
swift run Mimo
```

To prepare a profile and an Instagram bridge:

```bash
swift run MimoRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
swift run MimoRuntimeCLI bridge --profile demo --action install --network instagram
swift run MimoRuntimeCLI bridge --profile demo --action prepare --network instagram
swift build -c release
MIMO_PROFILE=demo swift run -c release Mimo
```

Add an account through **Settings → Add**. For CLI commands and options, run
`swift run MimoRuntimeCLI` to display usage.

To enable real-runtime integration tests:

```bash
MIMO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

## Generated files

Regenerate and commit after changing the corresponding sources:

```bash
swift Scripts/make-platform-glyphs.swift Scripts/brand-icons Sources/MimoUI/PlatformGlyphPaths.swift
swift Scripts/make-icon.swift docs/assets/mimo-mascot.png Resources/AppIcon.icns
swift run MimoRuntimeCLI sbom --output docs/sbom.cdx.json
```

## License

[AGPL-3.0-or-later](LICENSE). See the [third-party inventory](docs/dependencies.md).
