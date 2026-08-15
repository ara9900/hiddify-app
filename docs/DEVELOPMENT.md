# Development Guide

## Prerequisites

- Flutter **3.38.5+** / Dart **3.10.4+** (see `pubspec.yaml`)
- For Android: JDK, Android SDK
- For iOS/macOS: Xcode (macOS only)
- **Make** (Git Bash on Windows) for core download scripts

## First-time setup

```bash
# 1. Dependencies
flutter pub get

# 2. Code generation (Riverpod, Drift, assets, freezed…)
dart run build_runner build --delete-conflicting-outputs

# 3. Translations
dart run slang

# 4. Download hiddify-core binaries + geo assets
make android-prepare   # or: make windows-prepare, make ios-prepare, etc.
```

Without step 4, VPN core calls will fail — `hiddify-core/` and `assets/core/` are build artifacts.

## Run / build

```bash
# Debug (dev entry point)
flutter run

# Production entry
flutter run -t lib/main_prod.dart

# Release APK (after android-prepare)
make android-apk
```

Channel and entry point are controlled by Makefile `CHANNEL=prod|dev`.

## Project commands

| Command | Purpose |
|---------|---------|
| `make get` | `flutter pub get` |
| `make gen` | `build_runner` |
| `make translate` | Regenerate `translations.g.dart` |
| `make android-prepare` | Core + geo DBs for Android |
| `make android-apk` | Signed release APK |
| `make patch-ray2sing` | Apply Reality/Xray patches to `hiddify-core/ray2sing` |
| `make prepare-patched-core` | Clone pinned core deps + apply patches |
| `make build-android-libs` | gomobile AAR from local `hiddify-core` (Linux/CI) |

## Tests

```bash
flutter test
```

Tests live under `test/` — TikNet-specific tests in `test/features/tiknet/`.

Sample VPN configs for manual testing: `test.configs/`.

## TikNet debugging

### In-app diagnostic log

TikNet writes a ring buffer to `{workingDir}/tiknet_diagnostic.log`. View from **حساب من → گزارش تشخیصی** or pull via ADB:

```powershell
.\tools\adb_pull_tiknet_log.ps1
```

### Disable TikNet mode

In `lib/core/model/tiknet_config.dart`:

```dart
const bool tikNetMode = false;
```

Then `dart run build_runner build` and rebuild.

## Assets

Bundled images (see `pubspec.yaml`):

- `assets/images/logo.svg`
- `assets/images/tiknet_shield.png`
- `assets/images/tiknet_splash.png`

Optional emoji font for Windows flag rendering: see `assets/fonts/emoji_source.txt` (generate with `pyftsubset` — not required; app uses `Segoe UI Emoji` on Windows).

## Branding / IDs

| Layer | Value |
|-------|-------|
| User-facing name | TikNet (`Constants.appName`) |
| Dart package | `hiddify` |
| Android applicationId | `com.tik.net` |
| iOS bundle (Runner) | `com.tik.net` |
| Kotlin namespace | `com.hiddify.hiddify` (upstream) |
| macOS bundle (upstream) | `app.hiddify.com` — update if shipping macOS TikNet |

## CI / signing

APK signing uses GitHub Secrets — not committed keystore. See [TIKNET.md](../TIKNET.md) for `TIKNET_KEYSTORE_*` setup.

## Do not commit

- `build-output/` — local APKs and debug dumps (gitignored)
- `*.keystore`, `.github/signing/`
- `hiddify-core/bin/*`, `assets/core/*.db` (downloaded at build)
- Generated `*.g.dart` files

## Related docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — module layout
- [REALITY_RAY2SING.md](REALITY_RAY2SING.md) — Reality / ray2sing AAR patch + CI
- [TIKNET.md](../TIKNET.md) — panel API contract
- [CONTRIBUTING.md](../CONTRIBUTING.md) — upstream Hiddify contributor guide
