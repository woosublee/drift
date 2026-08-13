# Drift

[한국어](README.ko.md)

> Quiet, configurable cursor activity for macOS.

Drift is a native macOS menu bar utility that waits for idle time before performing configurable pointer movement and optional clicks. It stays out of the Dock, yields immediately to real keyboard or mouse input, and keeps every setting local to your Mac.

**macOS 13+ · Swift 5.10 · SwiftUI · Swift Package Manager**

## Highlights

- **Menu bar native** — Runs as a compact menu bar app with no Dock icon or standard app window.
- **Idle-aware automation** — `Start Moving After` and `Move Every` control when Drift begins and repeats activity.
- **Three motion profiles** — Silent performs a minimal out-and-back movement, Standard uses bounded linear movement, and Natural uses smoother curved paths with varied timing.
- **Optional clicks** — Supports Left, Right, and Alternating clicks at a saved screen position, then returns the pointer to its original location.
- **Automatic stop conditions** — Deactivate at selected times or below a configured battery level.
- **Fast control** — Toggle Drift from the popover, a global shortcut, or Launch at Login.
- **Input-first safety** — Physical mouse or keyboard input cancels active automation and resets the idle timer.
- **Local by default** — No analytics, no account, and no application network request in the default local build.

## How it works

1. Turn on **Active** from the menu bar popover.
2. Drift waits until the configured idle delay has elapsed.
3. It performs the selected movement or click sequence inside valid display bounds.
4. It waits for the configured repeat interval before the next sequence.
5. Real keyboard or mouse input cancels automation immediately and starts a fresh idle wait.

## Privacy and permissions

Drift needs macOS Accessibility permission to move the pointer and issue optional clicks. `Drift` and `Drift Dev` use separate Bundle IDs, so macOS manages their permissions and settings independently.

Drift includes no analytics. Production releases use Sparkle 2.9.2 to deliver signed updates from the stable release feed. Production artifacts use a self-signed `Drift` identity, so Gatekeeper may show a warning; they are not notarized. Development bundles contain neither a feed URL nor a Sparkle public key. See the [release runbook](docs/releasing.md) for the operator process, including dry-runs and publication safeguards.

## Install a release

Download the DMG from [GitHub Releases](https://github.com/woosublee/drift/releases), drag `Drift.app` into Applications, then Control-click the installed app and choose **Open** for the first launch. macOS may require this explicit confirmation because the current release is self-signed and not notarized. After Drift starts, use its menu-bar icon; it intentionally has no Dock icon or normal app window.

## Build and run

### Requirements

- macOS 13 or later
- Xcode Command Line Tools
- Swift 5.10 or later

Clone and test:

```bash
git clone https://github.com/woosublee/drift.git
cd drift
swift test
```

Create the stable local signing identity used for Accessibility testing:

```bash
make create-local-certificate
```

Build and verify `Drift Dev`:

```bash
make verify-app \
  CONFIGURATION=debug \
  BUILD_DIR=/tmp/drift-bundles/dev \
  CODESIGN_IDENTITY=Drift

open "/tmp/drift-bundles/dev/Drift Dev.app"
```

## Build variants

| Variant | App | Bundle ID | Default configuration |
|---|---|---|---|
| Production | `Drift.app` | `com.woosublee.drift` | `release` |
| Development | `Drift Dev.app` | `com.woosublee.drift.dev` | `debug` |

`APP_VARIANT=production|dev` can override the identity independently of the Swift build configuration. UserDefaults, Accessibility approval, Login Items, and LaunchServices remain separated by Bundle ID.

## Development and verification

Run the fresh test suite:

```bash
swift package clean
swift test
```

Verify both signed identities:

```bash
make verify-app \
  CONFIGURATION=debug \
  BUILD_DIR=/tmp/drift-bundles/dev \
  CODESIGN_IDENTITY=Drift

make verify-app \
  CONFIGURATION=release \
  BUILD_DIR=/tmp/drift-bundles/production \
  CODESIGN_IDENTITY=Drift
```

User-run macOS checks are documented in [docs/manual-verification.md](docs/manual-verification.md). Unchecked items are intentionally not presented as automated pass claims.
