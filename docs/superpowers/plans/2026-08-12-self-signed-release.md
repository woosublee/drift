# Drift Self-Signed Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Universal 2, self-signed Drift release pipeline that creates and verifies a versioned DMG, Sparkle appcast, and provenance locally and in GitHub Actions without publishing the first release until the user separately approves it.

**Architecture:** `release/version.json` is the sole version source. Focused shell scripts resolve identity, build and package release artifacts, validate Sparkle signatures and cross-artifact parity, and publish only already-existing annotated tags; both the local fallback and GitHub Actions call those same scripts. Swift process tests exercise scripts with isolated fixtures and fake external tools, while one final credential-backed dry-run validates the real Keychain identity and Sparkle key.

**Tech Stack:** Swift 5.10, Swift Package Manager, XCTest, zsh/bash, Python 3 standard library, macOS `codesign`/`security`/`hdiutil`/`lipo`/`plutil`, Sparkle 2.9.2 `sign_update`, GitHub CLI, GitHub Actions.

## Global Constraints

- Minimum supported OS remains macOS 13.0.
- Sparkle remains pinned exactly to 2.9.2.
- Production app identity remains `Drift` / `com.woosublee.drift`; development remains `Drift Dev` / `com.woosublee.drift.dev`.
- First release identity is marketing version `0.1.0`, build `1`, annotated tag `v0.1.0`.
- Release executable must contain exactly arm64 and x86_64 slices.
- Stable feed URL is `https://github.com/woosublee/drift/releases/latest/download/appcast.xml`.
- Release DMG URL format is `https://github.com/woosublee/drift/releases/download/v${RELEASE_VERSION}/Drift-${RELEASE_VERSION}.dmg`.
- The release artifacts are exactly `Drift-${RELEASE_VERSION}.dmg`, `appcast.xml`, and `release-provenance.json`.
- Release app, Sparkle nested code, Sparkle framework, and DMG use the existing self-signed identity `Drift` with hardened runtime where applicable.
- Development bundles continue to contain neither `SUFeedURL` nor `SUPublicEDKey`.
- No Developer ID signing, notarization, prerelease channel, `.pkg`, App Store path, key rotation automation, or generated changelog is added.
- Version, build, tag, release DMG path, and production Bundle ID cannot be overridden from Make or the environment.
- Private keys, `.p12` contents, and passwords must never be committed, printed, placed in provenance, or uploaded as workflow artifacts.
- Local and CI dry-runs must not create tags or GitHub Releases.
- The first `v0.1.0` Release requires a separate user confirmation after local and CI dry-runs pass.

---

## Planned File Structure

### Canonical release identity

- `release/version.json` — sole editable source for `marketingVersion` and `buildNumber`.
- `scripts/release-version-lib.sh` — validation, appcast parsing, integer comparison, atomic replacement, and canonical path helpers.
- `scripts/resolve-release-version.sh` — stable command-line interface for version, build, tag, paths, URLs, shell values, and JSON.
- `scripts/sync-release-version.sh` — atomically syncs or checks the two version keys in `Info.plist`.

### Build and package

- `scripts/build-universal-app.sh` — cross-builds both macOS triples, creates the fat executable, and delegates bundle assembly/signing to Make.
- `scripts/package-release-dmg.sh` — stages `Drift.app`, creates the Applications symlink, creates and signs the canonical DMG.
- `Makefile` — exposes narrow reusable targets for metadata checking, prebuilt bundle assembly, Universal 2 release app, and DMG packaging.
- `scripts/verify-app-bundle.sh` — keeps existing identity checks and gains explicit hardened-runtime/update metadata expectations where needed.

### Sparkle and artifact metadata

- `scripts/release-sparkle-lib.sh` — safely retrieves the private key, finds Sparkle 2.9.2 `sign_update`, and extracts enclosure fields.
- `scripts/validate-sparkle-key.swift` — derives the public key from a 32-byte seed or 96-byte Sparkle key and compares it with `SUPublicEDKey`.
- `scripts/generate-sparkle-appcast.sh` — validates the key pair, signs and re-verifies the DMG, and atomically writes the canonical appcast.
- `scripts/check-release-monotonic.sh` — fetches or accepts the previous stable appcast, requires a greater build, and writes normalized previous-release metadata.
- `scripts/generate-release-provenance.sh` — writes public build, signing, architecture, URL, length, and SHA-256 metadata.
- `scripts/verify-release-artifacts.sh` — validates source, app, mounted DMG app, appcast, Sparkle signature, and provenance as one release identity.

### Publication adapters

- `scripts/publish-github-release.sh` — publishes only an existing annotated tag and safely resumes only matching remote assets.
- `scripts/release-local.sh` — default dry-run orchestrator; `--publish` delegates to the publisher after stricter tag checks.
- `scripts/verify-published-release.sh` — downloads the three public assets and reuses the artifact verifier.
- `.github/workflows/release.yml` — tag publication plus manual dry-run/manual tag-ref publication using the same scripts.

### Tests and documentation

- `Tests/DriftAppTests/ReleaseVersionTests.swift` — canonical metadata, resolver, and sync behavior.
- `Tests/DriftAppTests/ReleaseBuildTests.swift` — dual-triple build, fat executable, and hardened signing contract.
- `Tests/DriftAppTests/ReleasePackagingTests.swift` — canonical DMG staging/signing behavior.
- `Tests/DriftAppTests/SparkleReleaseTests.swift` — private/public key matching, appcast generation, and signature verification invocation.
- `Tests/DriftAppTests/ReleaseMetadataTests.swift` — monotonicity and provenance schema.
- `Tests/DriftAppTests/ReleaseArtifactVerificationTests.swift` — parity and fail-closed verification.
- `Tests/DriftAppTests/ReleasePublishingTests.swift` — dry-run immutability, annotated-tag checks, and safe partial resume.
- `Tests/DriftAppTests/ReleaseWorkflowTests.swift` — workflow triggers, secrets, dry-run gating, cleanup, and shared-script use.
- `docs/releasing.md` — operator runbook and Gatekeeper/key continuity guidance.
- `README.md`, `README.ko.md` — public installation/update summary and release-doc link.

---

### Task 1: Establish the canonical release identity

**Files:**
- Create: `release/version.json`
- Create: `scripts/release-version-lib.sh`
- Create: `scripts/resolve-release-version.sh`
- Create: `scripts/sync-release-version.sh`
- Create: `Tests/DriftAppTests/ReleaseVersionTests.swift`
- Modify: `Makefile:1-31`
- Verify unchanged values: `Info.plist:19-22`

**Interfaces:**
- Consumes: `release/version.json` with exactly `marketingVersion: String` and `buildNumber: Int`.
- Produces: `release_load_identity "$REPO_ROOT"` setting `RELEASE_VERSION`, `RELEASE_BUILD`, `RELEASE_TAG`, `RELEASE_DMG_NAME`, `RELEASE_DMG_PATH`, `RELEASE_APPCAST_PATH`, `RELEASE_PROVENANCE_PATH`, `RELEASE_FEED_URL`, and `RELEASE_DOWNLOAD_URL`.
- Produces: `scripts/resolve-release-version.sh {validate|version|build|tag|dmg-name|dmg-path|appcast-path|provenance-path|feed-url|download-url|shell|json}`.
- Produces: `scripts/sync-release-version.sh [--check]`.
- Produces Make targets: `release-metadata-check`, `print-release-version`, `print-release-build`, `print-release-tag`.

- [ ] **Step 1: Write failing resolver and mirror tests**

Create `ReleaseVersionTests.swift` with fixture helpers that copy `Info.plist`, `release/version.json`, `release-version-lib.sh`, `resolve-release-version.sh`, and `sync-release-version.sh` into an isolated temporary repository. Add these assertions:

```swift
func testResolverReturnsCanonicalReleaseIdentity() throws {
    let fixture = try makeReleaseFixture()
    let result = try runScript("scripts/resolve-release-version.sh", ["json"], in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let data = try XCTUnwrap(result.output.data(using: .utf8))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["version"] as? String, "0.1.0")
    XCTAssertEqual(json["build"] as? Int, 1)
    XCTAssertEqual(json["tag"] as? String, "v0.1.0")
    XCTAssertEqual(json["dmgName"] as? String, "Drift-0.1.0.dmg")
    XCTAssertEqual(json["dmgPath"] as? String, "build/release/Drift-0.1.0.dmg")
    XCTAssertEqual(json["appcastPath"] as? String, "build/release/appcast.xml")
    XCTAssertEqual(json["provenancePath"] as? String, "build/release/release-provenance.json")
    XCTAssertEqual(json["feedURL"] as? String, "https://github.com/woosublee/drift/releases/latest/download/appcast.xml")
    XCTAssertEqual(json["downloadURL"] as? String, "https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg")
}

func testResolverRejectsUnknownKeysAndInvalidValues() throws {
    let fixture = try makeReleaseFixture(versionJSON: """
    {"marketingVersion":"01.0.0","buildNumber":0,"extra":true}
    """)
    let result = try runScript("scripts/resolve-release-version.sh", ["validate"], in: fixture)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("exactly marketingVersion and buildNumber"))
}

func testVersionMirrorCheckFailsWithoutMutatingPlist() throws {
    let fixture = try makeReleaseFixture(plistVersion: "9.9.9", plistBuild: "99")
    let plist = fixture.appendingPathComponent("Info.plist")
    let before = try Data(contentsOf: plist)

    let result = try runScript("scripts/sync-release-version.sh", ["--check"], in: fixture)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertEqual(try Data(contentsOf: plist), before)
    XCTAssertTrue(result.output.contains("Info.plist version mismatch"))
    XCTAssertTrue(result.output.contains("Info.plist build mismatch"))
}

func testVersionMirrorSyncUpdatesBothKeysAtomically() throws {
    let fixture = try makeReleaseFixture(plistVersion: "9.9.9", plistBuild: "99")
    let result = try runScript("scripts/sync-release-version.sh", [], in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let plist = try loadPlist(fixture.appendingPathComponent("Info.plist"))
    XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.1.0")
    XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
}
```

The test helper signatures are:

```swift
private func makeReleaseFixture(
    versionJSON: String = #"{"marketingVersion":"0.1.0","buildNumber":1}"#,
    plistVersion: String = "0.1.0",
    plistBuild: String = "1"
) throws -> URL

private func runScript(_ path: String, _ arguments: [String], in fixture: URL) throws -> TestProcessResult
private func loadPlist(_ url: URL) throws -> [String: Any]
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```bash
swift test --filter ReleaseVersionTests
```

Expected: FAIL because the metadata and resolver scripts do not exist.

- [ ] **Step 3: Add the canonical JSON and release identity library**

Create `release/version.json` exactly as:

```json
{
  "marketingVersion": "0.1.0",
  "buildNumber": 1
}
```

Implement `release-version-lib.sh` with these validations and derived values:

```bash
release_is_stable_semver() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

release_is_positive_int64() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
  (( ${#value} < 19 )) && return 0
  (( ${#value} > 19 )) && return 1
  [[ "$value" < 9223372036854775807 || "$value" == 9223372036854775807 ]]
}

release_load_identity() {
  local repo_root="$1"
  local metadata="$repo_root/release/version.json"
  python3 - "$metadata" <<'PY' >/dev/null
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
if type(value) is not dict or set(value) != {"marketingVersion", "buildNumber"}:
    raise SystemExit("ERROR: release/version.json must contain exactly marketingVersion and buildNumber")
if type(value["marketingVersion"]) is not str:
    raise SystemExit("ERROR: marketingVersion must be a JSON string")
if type(value["buildNumber"]) is not int or isinstance(value["buildNumber"], bool):
    raise SystemExit("ERROR: buildNumber must be a JSON integer")
PY
  RELEASE_VERSION="$(plutil -extract marketingVersion raw "$metadata")"
  RELEASE_BUILD="$(plutil -extract buildNumber raw "$metadata")"
  release_is_stable_semver "$RELEASE_VERSION" || release_fail 'marketingVersion must use stable SemVer x.y.z'
  release_is_positive_int64 "$RELEASE_BUILD" || release_fail 'buildNumber must be a positive 64-bit integer'
  RELEASE_TAG="v$RELEASE_VERSION"
  RELEASE_DMG_NAME="Drift-$RELEASE_VERSION.dmg"
  RELEASE_DMG_PATH="build/release/$RELEASE_DMG_NAME"
  RELEASE_APPCAST_PATH="build/release/appcast.xml"
  RELEASE_PROVENANCE_PATH="build/release/release-provenance.json"
  RELEASE_FEED_URL="https://github.com/woosublee/drift/releases/latest/download/appcast.xml"
  RELEASE_DOWNLOAD_URL="https://github.com/woosublee/drift/releases/download/$RELEASE_TAG/$RELEASE_DMG_NAME"
}
```

Also implement `release_fail`, `release_atomic_replace`, `release_positive_integer_greater_than`, and XML appcast parsing helpers in this file; later tasks must call these rather than duplicate parsing or comparison logic.

- [ ] **Step 4: Implement the resolver and atomic plist synchronizer**

`resolve-release-version.sh shell` must emit safely quoted assignments with these exact names:

```bash
printf "RELEASE_VERSION='%s'\n" "$RELEASE_VERSION"
printf "RELEASE_BUILD='%s'\n" "$RELEASE_BUILD"
printf "RELEASE_TAG='%s'\n" "$RELEASE_TAG"
printf "RELEASE_DMG_NAME='%s'\n" "$RELEASE_DMG_NAME"
printf "RELEASE_DMG_PATH='%s'\n" "$RELEASE_DMG_PATH"
printf "RELEASE_APPCAST_PATH='%s'\n" "$RELEASE_APPCAST_PATH"
printf "RELEASE_PROVENANCE_PATH='%s'\n" "$RELEASE_PROVENANCE_PATH"
printf "RELEASE_FEED_URL='%s'\n" "$RELEASE_FEED_URL"
printf "RELEASE_DOWNLOAD_URL='%s'\n" "$RELEASE_DOWNLOAD_URL"
```

`sync-release-version.sh --check` compares `CFBundleShortVersionString` and `CFBundleVersion`; sync mode copies the plist to a sibling temporary file, changes both keys with `plutil`, lints and re-reads it, then calls `release_atomic_replace`.

Modify the top of `Makefile` to reject command-line or environment definitions of `VERSION`, `BUILD_NUMBER`, `RELEASE_TAG`, `DMG_PATH`, and `BUNDLE_IDENTIFIER`, and add:

```make
RELEASE_RESOLVER := scripts/resolve-release-version.sh
RELEASE_VERSION := $(shell $(RELEASE_RESOLVER) version 2>/dev/null)
RELEASE_BUILD := $(shell $(RELEASE_RESOLVER) build 2>/dev/null)
RELEASE_TAG := $(shell $(RELEASE_RESOLVER) tag 2>/dev/null)

release-metadata-check:
	@$(RELEASE_RESOLVER) validate
	@scripts/sync-release-version.sh --check

print-release-version:
	@$(RELEASE_RESOLVER) version

print-release-build:
	@$(RELEASE_RESOLVER) build

print-release-tag:
	@$(RELEASE_RESOLVER) tag
```

- [ ] **Step 5: Run the focused and existing credential tests**

Run:

```bash
swift test --filter ReleaseVersionTests
swift test --filter ReleaseCredentialConfigurationTests
make -s release-metadata-check
```

Expected: all PASS, and metadata check prints no secret values.

- [ ] **Step 6: Commit the canonical identity slice**

```bash
git add release/version.json scripts/release-version-lib.sh scripts/resolve-release-version.sh scripts/sync-release-version.sh Tests/DriftAppTests/ReleaseVersionTests.swift Makefile Info.plist
git commit -m "feat: add canonical release identity"
```

---

### Task 2: Build and sign a Universal 2 release app

**Files:**
- Create: `scripts/build-universal-app.sh`
- Create: `Tests/DriftAppTests/ReleaseBuildTests.swift`
- Modify: `Makefile:154-226`
- Modify: `scripts/verify-app-bundle.sh:4-79`
- Modify: `Tests/DriftAppTests/BundleSigningMetadataTests.swift:24-41`

**Interfaces:**
- Consumes: Task 1 `resolve-release-version.sh shell` and existing build identity resolver.
- Produces: `scripts/build-universal-app.sh` with no positional arguments; tool paths may be replaced in tests through `SWIFT`, `LIPO`, and `MAKE`.
- Produces: canonical signed app at `build/release/Drift.app`.
- Produces Make target `bundle-prebuilt` consuming `PREBUILT_EXECUTABLE` and `PREBUILT_SPARKLE_FRAMEWORK`.
- Produces Make target `release-app` invoking the Universal builder.

- [ ] **Step 1: Write failing build-contract tests**

Create a test fixture with fake `swift`, `lipo`, and `make` executables that append arguments to a log and create requested outputs. Add:

```swift
func testUniversalBuilderUsesBothMacOSTriplesAndLiposTheirExecutables() throws {
    let fixture = try makeUniversalBuildFixture()
    let result = try runUniversalBuilder(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
    XCTAssertTrue(log.contains("--triple arm64-apple-macosx13.0"))
    XCTAssertTrue(log.contains("--triple x86_64-apple-macosx13.0"))
    XCTAssertTrue(log.contains("lipo -create"))
    XCTAssertTrue(log.contains("bundle-prebuilt"))
    XCTAssertTrue(log.contains("PREBUILT_EXECUTABLE="))
    XCTAssertTrue(log.contains("SPARKLE_FEED_URL=https://github.com/woosublee/drift/releases/latest/download/appcast.xml"))
}

func testReleaseSigningAppliesHardenedRuntimeToNestedCodeAndApp() throws {
    let makefile = try String(contentsOf: sourceRoot.appendingPathComponent("Makefile"))
    for path in ["Installer.xpc", "Downloader.xpc", "Autoupdate", "Updater.app", "Sparkle.framework"] {
        XCTAssertTrue(makefile.contains("--options runtime"), "Missing hardened runtime for \(path)")
    }
    XCTAssertTrue(makefile.contains("codesign --force --options runtime --sign \"$(CODESIGN_IDENTITY)\" \"$(APP_DIR)\""))
}
```

Update `BundleSigningMetadataTests` to search for the hardened-runtime framework and app signing commands instead of the old commands without `--options runtime`.

- [ ] **Step 2: Run tests and confirm the missing builder/signing behavior**

Run:

```bash
swift test --filter ReleaseBuildTests
swift test --filter BundleSigningMetadataTests
```

Expected: FAIL because `build-universal-app.sh`, `bundle-prebuilt`, and hardened-runtime signing do not exist.

- [ ] **Step 3: Split native compilation from bundle assembly in Make**

Refactor the current `app` recipe without changing its bundle layout:

```make
APP_EXECUTABLE ?= $(BIN_DIR)/Drift
SPARKLE_FRAMEWORK ?= $(shell find "$(BIN_DIR)" -type d -name Sparkle.framework -print -quit)
PREBUILT_EXECUTABLE ?=
PREBUILT_SPARKLE_FRAMEWORK ?=

swift-build: release-metadata-check
	$(SWIFT) build -c $(CONFIGURATION) --product Drift

app: swift-build
	$(MAKE) bundle-prebuilt \
		CONFIGURATION="$(CONFIGURATION)" APP_VARIANT="$(APP_VARIANT)" \
		BUILD_DIR="$(BUILD_DIR)" CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" \
		PREBUILT_EXECUTABLE="$(APP_EXECUTABLE)" \
		PREBUILT_SPARKLE_FRAMEWORK="$(SPARKLE_FRAMEWORK)" \
		SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" \
		SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"
```

Move the existing bundle creation and signing recipe under `bundle-prebuilt`, replace the copied executable/framework paths with the two required prebuilt inputs, and fail if either is missing. For a non-ad-hoc identity, sign nested Sparkle code, framework, and final app with `--options runtime`. Preserve the explicit designated requirement only for `CODESIGN_IDENTITY=-` development builds.

- [ ] **Step 4: Implement the dual-triple build script**

Implement this sequence in `build-universal-app.sh`:

```bash
eval "$("$SCRIPT_DIR/resolve-release-version.sh" shell)"
release_root="$REPO_ROOT/build/release"
arm_scratch="$release_root/swift-arm64"
x86_scratch="$release_root/swift-x86_64"
universal_executable="$release_root/universal/Drift"

"$SWIFT" build -c release --product Drift \
  --scratch-path "$arm_scratch" --triple arm64-apple-macosx13.0
"$SWIFT" build -c release --product Drift \
  --scratch-path "$x86_scratch" --triple x86_64-apple-macosx13.0
arm_bin="$($SWIFT build -c release --show-bin-path --scratch-path "$arm_scratch" --triple arm64-apple-macosx13.0)"
x86_bin="$($SWIFT build -c release --show-bin-path --scratch-path "$x86_scratch" --triple x86_64-apple-macosx13.0)"
mkdir -p "${universal_executable%/*}"
"$LIPO" -create "$arm_bin/Drift" "$x86_bin/Drift" -output "$universal_executable"
```

Find `Sparkle.framework` under the arm64 scratch artifact tree, then invoke:

```bash
"$MAKE" -C "$REPO_ROOT" bundle-prebuilt \
  CONFIGURATION=release APP_VARIANT=production BUILD_DIR="$release_root" \
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Drift}" \
  PREBUILT_EXECUTABLE="$universal_executable" \
  PREBUILT_SPARKLE_FRAMEWORK="$sparkle_framework" \
  SPARKLE_FEED_URL="$RELEASE_FEED_URL" \
  SPARKLE_PUBLIC_ED_KEY="$(plutil -extract SUPublicEDKey raw "$REPO_ROOT/Info.plist")"
```

Finally require `lipo -archs build/release/Drift.app/Contents/MacOS/Drift` to normalize to exactly `arm64 x86_64`, then run `verify-app-bundle.sh` in `production-configured` mode.

Add:

```make
release-app: release-metadata-check
	@scripts/build-universal-app.sh
```

- [ ] **Step 5: Run focused tests and build each target compiler slice**

Run:

```bash
swift test --filter ReleaseBuildTests
swift test --filter BundleSigningMetadataTests
swift test --filter AppBundleTests
xcrun --sdk macosx swiftc -print-target-info -target arm64-apple-macosx13.0 >/dev/null
xcrun --sdk macosx swiftc -print-target-info -target x86_64-apple-macosx13.0 >/dev/null
```

Expected: all tests and target-info checks PASS.

- [ ] **Step 6: Commit the Universal app slice**

```bash
git add scripts/build-universal-app.sh Makefile scripts/verify-app-bundle.sh Tests/DriftAppTests/ReleaseBuildTests.swift Tests/DriftAppTests/BundleSigningMetadataTests.swift
git commit -m "feat: build universal self-signed app"
```

---

### Task 3: Package and sign the canonical DMG

**Files:**
- Create: `scripts/package-release-dmg.sh`
- Create: `Tests/DriftAppTests/ReleasePackagingTests.swift`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `build/release/Drift.app` from Task 2 and canonical paths from Task 1.
- Produces: signed `build/release/Drift-${RELEASE_VERSION}.dmg`.
- Produces: `scripts/package-release-dmg.sh` with test-replaceable `HDIUTIL`, `CODESIGN`, and `DITTO`.
- Produces Make targets `release-dmg` and `verify-release-dmg`.

- [ ] **Step 1: Write failing canonical packaging tests**

Use fake tools that log their arguments and make the DMG output file. Add:

```swift
func testPackagerStagesAppAndApplicationsLinkUnderCanonicalName() throws {
    let fixture = try makePackagingFixture()
    let result = try runPackager(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
    XCTAssertTrue(log.contains("Drift.app"))
    XCTAssertTrue(log.contains("Applications -> /Applications"))
    XCTAssertTrue(log.contains("-volname Drift"))
    XCTAssertTrue(log.contains("Drift-0.1.0.dmg"))
}

func testPackagerSignsAndStrictlyVerifiesTheDMG() throws {
    let fixture = try makePackagingFixture()
    let result = try runPackager(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
    let sign = try XCTUnwrap(log.range(of: "codesign --force --sign Drift"))
    let verify = try XCTUnwrap(log.range(of: "codesign --verify --strict"))
    XCTAssertLessThan(sign.lowerBound, verify.lowerBound)
}
```

- [ ] **Step 2: Run the packaging tests and confirm failure**

Run:

```bash
swift test --filter ReleasePackagingTests
```

Expected: FAIL because the packaging script and targets do not exist.

- [ ] **Step 3: Implement atomic staging, DMG creation, signing, and verification**

`package-release-dmg.sh` must:

```bash
eval "$("$SCRIPT_DIR/resolve-release-version.sh" shell)"
app="$REPO_ROOT/build/release/Drift.app"
dmg="$REPO_ROOT/$RELEASE_DMG_PATH"
staging="$(mktemp -d "${TMPDIR:-/tmp}/drift-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
"$DITTO" --norsrc --noextattr "$app" "$staging/Drift.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
"$HDIUTIL" create -volname Drift -srcfolder "$staging" -ov -format UDZO "$dmg"
"$CODESIGN" --force --sign "${CODESIGN_IDENTITY:-Drift}" "$dmg"
"$CODESIGN" --verify --strict --verbose=2 "$dmg"
```

Before DMG creation, run `verify-bundle-signing-xattrs.sh` and `codesign --verify --deep --strict` on the staged app. Never use `--clobber`, an unversioned DMG name, or a source folder outside the temporary staging directory.

Add:

```make
release-dmg: release-app
	@scripts/package-release-dmg.sh

verify-release-dmg: release-dmg
	@codesign --verify --strict --verbose=2 "$$(scripts/resolve-release-version.sh dmg-path)"
```

- [ ] **Step 4: Run the focused tests and static shell validation**

Run:

```bash
swift test --filter ReleasePackagingTests
zsh -n scripts/package-release-dmg.sh
make -n release-dmg | grep -F 'scripts/package-release-dmg.sh'
```

Expected: PASS; Make dry-run shows the shared packager.

- [ ] **Step 5: Commit the DMG slice**

```bash
git add scripts/package-release-dmg.sh Tests/DriftAppTests/ReleasePackagingTests.swift Makefile
git commit -m "feat: package signed release dmg"
```

---

### Task 4: Generate and cryptographically verify the Sparkle appcast

**Files:**
- Create: `scripts/release-sparkle-lib.sh`
- Create: `scripts/validate-sparkle-key.swift`
- Create: `scripts/generate-sparkle-appcast.sh`
- Create: `Tests/DriftAppTests/SparkleReleaseTests.swift`
- Modify: `Makefile`

**Interfaces:**
- Consumes: canonical DMG and URLs from Task 1/3, `Info.plist` `SUPublicEDKey`, either `SPARKLE_PRIVATE_KEY` or Keychain service/account.
- Produces: `release_sparkle_private_key`, `release_find_sign_update`, and `release_verify_signature "$dmg" "$signature"` in `release-sparkle-lib.sh`.
- Produces: atomic `build/release/appcast.xml`.
- Produces Make target `release-appcast`.

- [ ] **Step 1: Write failing key and appcast tests with a fixed non-secret test key**

Use this deterministic test-only pair:

```text
Private seed: AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=
Public key:  iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w=
```

Add:

```swift
func testSparkleKeyValidatorAcceptsMatchingSeedAndRejectsMismatch() throws {
    let matching = try runValidator(privateKey: testPrivateSeed, publicKey: testPublicKey)
    XCTAssertEqual(matching.status, 0, matching.output)

    let mismatch = try runValidator(
        privateKey: testPrivateSeed,
        publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    )
    XCTAssertNotEqual(mismatch.status, 0)
    XCTAssertTrue(mismatch.output.contains("does not match SUPublicEDKey"))
}

func testAppcastGeneratorSignsThenVerifiesAndWritesCanonicalEnclosure() throws {
    let fixture = try makeSparkleFixture()
    let result = try runGenerator(in: fixture, privateKey: testPrivateSeed)

    XCTAssertEqual(result.status, 0, result.output)
    let appcast = try String(contentsOf: fixture.appendingPathComponent("build/release/appcast.xml"))
    XCTAssertTrue(appcast.contains("<sparkle:version>1</sparkle:version>"))
    XCTAssertTrue(appcast.contains("<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>"))
    XCTAssertTrue(appcast.contains("https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg"))
    XCTAssertTrue(appcast.contains("sparkle:edSignature=\"TEST_SIGNATURE\""))
    let log = try String(contentsOf: fixture.appendingPathComponent("sign-update.log"))
    XCTAssertTrue(log.contains("SIGN"))
    XCTAssertTrue(log.contains("VERIFY TEST_SIGNATURE"))
}
```

The fake `sign_update` returns `sparkle:edSignature="TEST_SIGNATURE"` in sign mode and exits zero only when verify mode receives the same signature.

- [ ] **Step 2: Run tests and confirm the missing signing pipeline**

Run:

```bash
swift test --filter SparkleReleaseTests
```

Expected: FAIL because validator, library, and generator do not exist.

- [ ] **Step 3: Implement the private/public key validator**

Use CryptoKit exactly as follows:

```swift
let secretInput = FileHandle.standardInput.readDataToEndOfFile()
let secretString = String(decoding: secretInput, as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let secret = Data(base64Encoded: secretString) else {
    fail("Sparkle private key is not valid base64")
}
let derived: Data
switch secret.count {
case 32:
    derived = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
        .publicKey.rawRepresentation
case 96:
    derived = secret.suffix(32)
default:
    fail("Sparkle private key must decode to 32 or 96 bytes")
}
guard derived == expected else {
    fail("Sparkle private key does not match SUPublicEDKey")
}
```

The validator reads the private key only from stdin and never prints it.

- [ ] **Step 4: Implement shared Sparkle lookup and appcast generation**

`release_sparkle_private_key` uses `SPARKLE_PRIVATE_KEY` when non-empty; otherwise it calls:

```bash
security find-generic-password \
  -s "${SPARKLE_KEYCHAIN_SERVICE:-https://sparkle-project.org}" \
  -a "${SPARKLE_ACCOUNT:-com.woosublee.drift.sparkle.ed25519}" \
  -w 2>/dev/null
```

`release_find_sign_update` first accepts an executable `SPARKLE_SIGN_UPDATE`, then searches `.build/artifacts` for an executable named `sign_update`; it must not download a different Sparkle version.

`generate-sparkle-appcast.sh` performs this exact order:

1. Resolve canonical identity and require the canonical DMG.
2. Read `SUPublicEDKey` from source `Info.plist`.
3. Pipe the private key to `xcrun swift scripts/validate-sparkle-key.swift "$expected_public_key"`.
4. Pipe the key to `"$SIGN_UPDATE" "$CANONICAL_DMG_PATH" --ed-key-file -` and parse one signature.
5. Pipe the key to `"$SIGN_UPDATE" --verify --ed-key-file - "$CANONICAL_DMG_PATH" "$ed_signature"`.
6. Compute `wc -c`, UTC RFC 2822 publication time, and the canonical download URL.
7. Write XML to a temporary sibling file, validate it with `xmllint --noout`, and atomically replace `build/release/appcast.xml`.

Use both item-level and enclosure-level version values, plus `sparkle:releaseNotesLink` pointing at `https://github.com/woosublee/drift/releases/tag/v0.1.0`.

Add:

```make
release-appcast: release-dmg
	@scripts/generate-sparkle-appcast.sh
```

- [ ] **Step 5: Run cryptographic and appcast tests**

Run:

```bash
swift test --filter SparkleReleaseTests
zsh -n scripts/generate-sparkle-appcast.sh
xcrun swift scripts/validate-sparkle-key.swift iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w= \
  <<< 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
```

Expected: all PASS and no private key text in output.

- [ ] **Step 6: Commit the Sparkle slice**

```bash
git add scripts/release-sparkle-lib.sh scripts/validate-sparkle-key.swift scripts/generate-sparkle-appcast.sh Tests/DriftAppTests/SparkleReleaseTests.swift Makefile
git commit -m "feat: generate verified sparkle appcast"
```

---

### Task 5: Enforce build monotonicity and generate provenance

**Files:**
- Create: `scripts/check-release-monotonic.sh`
- Create: `scripts/generate-release-provenance.sh`
- Create: `Tests/DriftAppTests/ReleaseMetadataTests.swift`
- Modify: `scripts/release-version-lib.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: current canonical identity, optional `--previous-appcast FILE`, or latest non-draft/non-prerelease GitHub Release.
- Produces: `scripts/check-release-monotonic.sh --repository OWNER/REPO [--previous-appcast FILE] [--exclude-tag TAG] --output FILE`.
- Produces normalized `build/release/previous-release.json`, with `previous: null` for the first release.
- Produces: `scripts/generate-release-provenance.sh --previous FILE` writing the canonical provenance path.
- Produces Make target `release-provenance`.

- [ ] **Step 1: Write failing first-release, regression, and provenance tests**

Add fake `gh`, `git`, `codesign`, and `lipo` tools where needed. Assert:

```swift
func testFirstReleaseWritesNullPreviousMetadata() throws {
    let fixture = try makeMetadataFixture(fakeGitHubReleases: [])
    let result = try runMonotonicCheck(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let metadata = try loadJSON(fixture.appendingPathComponent("build/release/previous-release.json"))
    XCTAssertTrue(metadata["previous"] is NSNull)
    XCTAssertEqual(metadata["source"] as? String, "no-previous-release")
}

func testCandidateBuildMustBeGreaterThanPreviousAppcastBuild() throws {
    let fixture = try makeMetadataFixture(candidateBuild: 1, previousBuild: 1)
    let result = try runMonotonicCheck(in: fixture, explicitPreviousAppcast: true)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("current build 1 must be greater than previous build 1"))
}

func testProvenanceContainsOnlyPublicCanonicalMetadata() throws {
    let fixture = try makeCompleteArtifactFixture()
    let result = try runProvenanceGenerator(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
    let value = try loadJSON(fixture.appendingPathComponent("build/release/release-provenance.json"))
    let release = try XCTUnwrap(value["release"] as? [String: Any])
    XCTAssertEqual(release["version"] as? String, "0.1.0")
    XCTAssertEqual(release["build"] as? Int, 1)
    XCTAssertEqual(release["tag"] as? String, "v0.1.0")
    XCTAssertEqual(release["architectures"] as? [String], ["arm64", "x86_64"])
    XCTAssertNil(value["privateKey"])
    XCTAssertFalse(String(data: try Data(contentsOf: fixture.appendingPathComponent("build/release/release-provenance.json")), encoding: .utf8)!.contains(testPrivateSeed))
}
```

- [ ] **Step 2: Run metadata tests and confirm failure**

Run:

```bash
swift test --filter ReleaseMetadataTests
```

Expected: FAIL because monotonicity and provenance scripts do not exist.

- [ ] **Step 3: Implement previous stable release resolution and build comparison**

The monotonicity script must:

- Validate repository as `OWNER/REPO`.
- If `--previous-appcast` is present, parse only that local file and record source `explicit-previous-appcast`.
- Otherwise use `gh release list --exclude-drafts --exclude-pre-releases --json tagName,publishedAt` and download `appcast.xml` from the most recently published stable tag excluding `--exclude-tag`.
- Require the appcast tag to match the selected Release tag.
- Call `release_positive_integer_greater_than "$RELEASE_BUILD" "$APPCAST_BUILD"` when a previous release exists.
- Atomically write:

```json
{
  "source": "no-previous-release",
  "previous": null
}
```

or:

```json
{
  "source": "github-release-appcast",
  "previous": {
    "version": "0.0.9",
    "build": 9,
    "tag": "v0.0.9",
    "dmgName": "Drift-0.0.9.dmg"
  }
}
```

- [ ] **Step 4: Implement deterministic public provenance generation**

Generate this schema with Python JSON serialization and sorted keys:

```json
{
  "schemaVersion": 1,
  "release": {
    "version": "0.1.0",
    "build": 1,
    "tag": "v0.1.0",
    "commit": "0123456789abcdef0123456789abcdef01234567",
    "repository": "woosublee/drift",
    "bundleIdentifier": "com.woosublee.drift",
    "architectures": ["arm64", "x86_64"],
    "feedURL": "https://github.com/woosublee/drift/releases/latest/download/appcast.xml",
    "downloadURL": "https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg"
  },
  "signing": {
    "certificateCommonName": "Drift",
    "certificateSHA256": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "sparklePublicKey": "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="
  },
  "artifacts": {
    "dmg": {"name": "Drift-0.1.0.dmg", "bytes": 1, "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
    "appcast": {"name": "appcast.xml", "bytes": 1, "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
  },
  "build": {
    "timestamp": "2026-08-12T00:00:00Z",
    "workflowRunID": null
  },
  "previous": null
}
```

Extract the signing certificate from the signed app with `codesign --extract-certificates` into a private temporary directory, convert the first DER certificate with `openssl x509`, and compute its SHA-256 fingerprint. Do not query or serialize private key material. Accept `SOURCE_DATE_EPOCH` and `GITHUB_RUN_ID` so tests and CI can produce controlled metadata.

Add:

```make
release-provenance: release-appcast
	@scripts/check-release-monotonic.sh --repository woosublee/drift --output build/release/previous-release.json
	@scripts/generate-release-provenance.sh --previous build/release/previous-release.json
```

- [ ] **Step 5: Run metadata tests and schema checks**

Run:

```bash
swift test --filter ReleaseMetadataTests
zsh -n scripts/check-release-monotonic.sh
zsh -n scripts/generate-release-provenance.sh
```

Expected: PASS.

- [ ] **Step 6: Commit monotonicity and provenance**

```bash
git add scripts/check-release-monotonic.sh scripts/generate-release-provenance.sh scripts/release-version-lib.sh Tests/DriftAppTests/ReleaseMetadataTests.swift Makefile
git commit -m "feat: verify release ordering and provenance"
```

---

### Task 6: Verify all release artifacts as one identity

**Files:**
- Create: `scripts/verify-release-artifacts.sh`
- Create: `Tests/DriftAppTests/ReleaseArtifactVerificationTests.swift`
- Modify: `scripts/release-version-lib.sh`
- Modify: `scripts/verify-app-bundle.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `--source-plist`, `--app`, `--dmg`, `--appcast`, `--provenance`, and optional `--previous-appcast`.
- Produces: zero exit only when every supplied artifact matches the canonical release and required security checks pass.
- Produces Make target `verify-release-artifacts`.

- [ ] **Step 1: Write failing pass/fail artifact fixtures**

Create a complete synthetic fixture with a fake mounted `Drift.app`, canonical plist, DMG, appcast, provenance, and fake macOS tools. Add:

```swift
func testVerifierAcceptsACompleteCanonicalRelease() throws {
    let fixture = try makeArtifactVerificationFixture()
    let result = try runVerifier(in: fixture)

    XCTAssertEqual(result.status, 0, result.output)
}

func testVerifierRejectsNonUniversalExecutable() throws {
    let fixture = try makeArtifactVerificationFixture(architectures: ["arm64"])
    let result = try runVerifier(in: fixture)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("architectures mismatch: expected arm64 x86_64"))
}

func testVerifierRejectsAppcastLengthOrSignatureMismatch() throws {
    let fixture = try makeArtifactVerificationFixture(appcastLengthDelta: 1, verifySignature: false)
    let result = try runVerifier(in: fixture)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("appcast enclosure length mismatch") || result.output.contains("Sparkle signature verification failed"))
}

func testVerifierRejectsProvenanceHashMismatch() throws {
    let fixture = try makeArtifactVerificationFixture(provenanceDMGSHA256: String(repeating: "0", count: 64))
    let result = try runVerifier(in: fixture)

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("provenance DMG SHA-256 mismatch"))
}
```

- [ ] **Step 2: Run verification tests and confirm failure**

Run:

```bash
swift test --filter ReleaseArtifactVerificationTests
```

Expected: FAIL because the aggregate verifier does not exist.

- [ ] **Step 3: Implement source, app, DMG, and appcast verification**

The verifier must perform, in this order:

1. Load canonical release identity and check `Info.plist` mirror.
2. Validate source plist version/build and 32-byte `SUPublicEDKey`.
3. Validate built app version/build/Bundle ID/feed/public key.
4. Require `lipo -archs` to normalize to `arm64 x86_64`.
5. Run `codesign --verify --deep --strict --verbose=2` on the app and `codesign --verify --strict --verbose=2` on the DMG.
6. Mount the DMG readonly/nobrowse into a temporary mount point and repeat app plist, architecture, update metadata, and signature checks.
7. Parse the first appcast item and require item/enclosure version `0.1.0`, build `1`, canonical URL, canonical DMG filename, exact byte length, one non-empty EdDSA signature, and `application/octet-stream`.
8. Pipe the private key to `"$SIGN_UPDATE" --verify --ed-key-file - "$dmg" "$signature"` and replace any tool error with `ERROR: Sparkle signature verification failed` without exposing stderr that may include secret-related context.
9. If `--previous-appcast` is supplied, require current build to be greater.
10. Always detach the DMG, falling back to forced detach only during cleanup.

- [ ] **Step 4: Implement provenance parity verification**

Use Python to load provenance and compare exact values for:

- schema version
- version/build/tag/commit/repository/Bundle ID
- sorted architectures
- feed and download URLs
- certificate common name/fingerprint extracted from the app
- Sparkle public key
- DMG/appcast names, byte lengths, SHA-256 values
- normalized previous-release object

Reject unknown top-level keys so provenance cannot silently gain private or unrelated data. The only accepted top-level key set is:

```python
{
    "schemaVersion", "release", "signing", "artifacts", "build", "previous"
}
```

Add:

```make
verify-release-artifacts: release-provenance
	@scripts/verify-release-artifacts.sh \
		--source-plist Info.plist \
		--app build/release/Drift.app \
		--dmg "$$(scripts/resolve-release-version.sh dmg-path)" \
		--appcast "$$(scripts/resolve-release-version.sh appcast-path)" \
		--provenance "$$(scripts/resolve-release-version.sh provenance-path)"
```

- [ ] **Step 5: Run focused and existing bundle tests**

Run:

```bash
swift test --filter ReleaseArtifactVerificationTests
swift test --filter AppBundleTests
swift test --filter BundleSigningMetadataTests
zsh -n scripts/verify-release-artifacts.sh
```

Expected: PASS.

- [ ] **Step 6: Commit the aggregate verifier**

```bash
git add scripts/verify-release-artifacts.sh scripts/release-version-lib.sh scripts/verify-app-bundle.sh Tests/DriftAppTests/ReleaseArtifactVerificationTests.swift Makefile
git commit -m "feat: verify release artifact parity"
```

---

### Task 7: Add safe GitHub publication and local fallback adapters

**Files:**
- Create: `scripts/publish-github-release.sh`
- Create: `scripts/release-local.sh`
- Create: `scripts/verify-published-release.sh`
- Create: `Tests/DriftAppTests/ReleasePublishingTests.swift`
- Modify: `Makefile`

**Interfaces:**
- Consumes: verified canonical artifacts from Task 6 and an existing annotated tag for publication.
- Produces: `scripts/publish-github-release.sh --repository OWNER/REPO --tag TAG --notes FILE`.
- Produces: `scripts/release-local.sh [--publish] [--previous-appcast FILE]`.
- Produces: `scripts/verify-published-release.sh --repository OWNER/REPO --tag TAG`.
- Produces Make target `release-dry-run` only; no Make target may publish implicitly.

- [ ] **Step 1: Write failing dry-run, tag, and partial-resume tests**

Use fake `git` and `gh` commands that append mutations to a log. Add:

```swift
func testLocalReleaseDefaultsToDryRunWithoutGitHubMutation() throws {
    let fixture = try makePublishingFixture()
    let result = try runLocalRelease(in: fixture, arguments: [])

    XCTAssertEqual(result.status, 0, result.output)
    XCTAssertTrue(result.output.contains("Dry-run complete; no tag or GitHub Release was created"))
    let mutations = (try? String(contentsOf: fixture.appendingPathComponent("mutations.log"))) ?? ""
    XCTAssertEqual(mutations, "")
}

func testPublishRequiresExistingAnnotatedTagOnCurrentCommitAndOrigin() throws {
    let fixture = try makePublishingFixture(localTagType: "commit")
    let result = try runLocalRelease(in: fixture, arguments: ["--publish"])

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("release tag must be annotated"))
}

func testPublisherResumesOnlyMatchingAssetsAndRejectsDifferentChecksums() throws {
    let matching = try makePublishingFixture(existingAssets: [.dmgMatching])
    XCTAssertEqual(try runPublisher(in: matching).status, 0)
    XCTAssertEqual(try uploadedAssetNames(in: matching), ["appcast.xml", "release-provenance.json"])

    let conflicting = try makePublishingFixture(existingAssets: [.dmgConflicting])
    let result = try runPublisher(in: conflicting)
    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(result.output.contains("existing asset checksum mismatch"))
}
```

- [ ] **Step 2: Run publishing tests and confirm failure**

Run:

```bash
swift test --filter ReleasePublishingTests
```

Expected: FAIL because publication adapters do not exist.

- [ ] **Step 3: Implement the GitHub publisher with no clobber path**

`publish-github-release.sh` must:

- Require the supplied tag to equal `RELEASE_TAG`.
- Require `git cat-file -t refs/tags/$tag` to equal `tag`, proving it is annotated.
- Require `git rev-list -n 1 refs/tags/$tag` to equal `HEAD`.
- Resolve the peeled remote tag with `git ls-remote --tags origin refs/tags/$tag refs/tags/$tag^{}` and require it to equal `HEAD`.
- If no Release exists, create it with `gh release create "$tag" --verify-tag --latest --title "Drift $RELEASE_VERSION" --notes-file "$notes"`.
- If a Release exists, require non-draft, non-prerelease status and title `Drift $RELEASE_VERSION`.
- For each canonical asset, download an existing remote asset to a temporary directory and compare SHA-256; accept matching files, upload missing files, and fail on mismatches.
- Never use `--clobber`, delete a Release, delete a tag, edit unexpected metadata, or create/push a tag.

- [ ] **Step 4: Implement local dry-run and published verification**

`release-local.sh` performs:

```text
clean working tree check
release metadata check
repository identity check
swift test
credential profile check
Sparkle key-pair check
monotonicity preflight
make verify-release-artifacts
monotonicity recheck
remote tag/release recheck
```

In default mode it stops with the exact dry-run completion message. With `--publish`, it additionally requires the annotated local/remote tag checks and calls the publisher.

`verify-published-release.sh` downloads only the three canonical assets from the specified tag, verifies their checksums against provenance, calls `verify-release-artifacts.sh` on the downloaded DMG/appcast/provenance, and fetches `releases/latest/download/appcast.xml` with bounded retries of 5, 10, 20, and 30 seconds. It must compare the latest appcast SHA-256 with the tagged appcast and fail after the fourth attempt.

Add:

```make
release-dry-run:
	@scripts/release-local.sh
```

- [ ] **Step 5: Run publishing tests and shell validation**

Run:

```bash
swift test --filter ReleasePublishingTests
zsh -n scripts/publish-github-release.sh
zsh -n scripts/release-local.sh
zsh -n scripts/verify-published-release.sh
```

Expected: PASS and no mutation log in dry-run tests.

- [ ] **Step 6: Commit publication adapters**

```bash
git add scripts/publish-github-release.sh scripts/release-local.sh scripts/verify-published-release.sh Tests/DriftAppTests/ReleasePublishingTests.swift Makefile
git commit -m "feat: add safe release publication adapters"
```

---

### Task 8: Add the shared-script GitHub Actions workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `Tests/DriftAppTests/ReleaseWorkflowTests.swift`

**Interfaces:**
- Consumes repository secrets `DRIFT_CERTIFICATE_BASE64`, `DRIFT_CERTIFICATE_PASSWORD`, and `SPARKLE_PRIVATE_KEY`.
- Consumes the scripts and Make targets from Tasks 1-7.
- Produces tag-triggered publication, manual dry-run by default, and manual publication only when invoked on the canonical tag ref with `publish=true`.

- [ ] **Step 1: Write failing workflow contract tests**

Read the workflow as text and assert the security-critical structure:

```swift
func testWorkflowSupportsTagPublishAndManualDryRun() throws {
    let workflow = try sourceWorkflow()
    XCTAssertTrue(workflow.contains("push:"))
    XCTAssertTrue(workflow.contains("tags:"))
    XCTAssertTrue(workflow.contains("- 'v*'"))
    XCTAssertTrue(workflow.contains("workflow_dispatch:"))
    XCTAssertTrue(workflow.contains("publish:"))
    XCTAssertTrue(workflow.contains("default: false"))
    XCTAssertTrue(workflow.contains("cancel-in-progress: false"))
}

func testWorkflowUsesCanonicalSecretsAndSharedScripts() throws {
    let workflow = try sourceWorkflow()
    for secret in ["DRIFT_CERTIFICATE_BASE64", "DRIFT_CERTIFICATE_PASSWORD", "SPARKLE_PRIVATE_KEY"] {
        XCTAssertTrue(workflow.contains("secrets.\(secret)"))
    }
    XCTAssertTrue(workflow.contains("scripts/check-release-monotonic.sh"))
    XCTAssertTrue(workflow.contains("make verify-release-artifacts"))
    XCTAssertTrue(workflow.contains("scripts/publish-github-release.sh"))
    XCTAssertTrue(workflow.contains("scripts/verify-published-release.sh"))
    XCTAssertFalse(workflow.contains("set -x"))
    XCTAssertFalse(workflow.contains("--clobber"))
}

func testWorkflowAlwaysCleansTemporaryCertificateAndKeychain() throws {
    let workflow = try sourceWorkflow()
    XCTAssertTrue(workflow.contains("if: always()"))
    XCTAssertTrue(workflow.contains("security default-keychain -d user -s \"$ORIGINAL_DEFAULT_KEYCHAIN\""))
    XCTAssertTrue(workflow.contains("security list-keychains -d user -s $ORIGINAL_KEYCHAINS"))
    XCTAssertTrue(workflow.contains("security delete-keychain"))
    XCTAssertTrue(workflow.contains("rm -f \"$RUNNER_TEMP/drift-certificate.p12\""))
}
```

- [ ] **Step 2: Run the workflow tests and confirm failure**

Run:

```bash
swift test --filter ReleaseWorkflowTests
```

Expected: FAIL because `.github/workflows/release.yml` does not exist.

- [ ] **Step 3: Implement triggers, concurrency, and immutable publish gating**

The workflow starts with:

```yaml
name: Self-signed Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      publish:
        description: Publish the already-selected canonical tag
        required: true
        type: boolean
        default: false

permissions:
  contents: write

concurrency:
  group: drift-stable-release
  cancel-in-progress: false
```

Resolve `publish_requested=true` for tag pushes, or from the Boolean input for manual runs. A manual publish must satisfy:

```bash
[[ "$GITHUB_REF" == "refs/tags/$RELEASE_TAG" ]]
[[ "$(git rev-list -n 1 "$RELEASE_TAG")" == "$GITHUB_SHA" ]]
```

Manual dry-run may run on a branch and must skip all GitHub Release mutation steps.

- [ ] **Step 4: Implement secret import, build, artifact upload, publication, and cleanup**

Use `macos-latest`, `actions/checkout@v4` with full history, and `actions/upload-artifact@v4`. Keep release logic in repository scripts.

Certificate import rules:

```bash
[[ -n "$CERTIFICATE_BASE64" ]] || { echo 'DRIFT_CERTIFICATE_BASE64 secret is required' >&2; exit 1; }
[[ -n "$CERTIFICATE_PASSWORD" ]] || { echo 'DRIFT_CERTIFICATE_PASSWORD secret is required' >&2; exit 1; }
[[ -n "$SPARKLE_PRIVATE_KEY" ]] || { echo 'SPARKLE_PRIVATE_KEY secret is required' >&2; exit 1; }
echo "::add-mask::$CERTIFICATE_BASE64"
echo "::add-mask::$CERTIFICATE_PASSWORD"
echo "::add-mask::$SPARKLE_PRIVATE_KEY"
printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/drift-certificate.p12"
ORIGINAL_DEFAULT_KEYCHAIN="$(security default-keychain -d user | tr -d '\"')"
ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '\"')"
printf 'ORIGINAL_DEFAULT_KEYCHAIN=%s\n' "$ORIGINAL_DEFAULT_KEYCHAIN" >> "$GITHUB_ENV"
printf 'ORIGINAL_KEYCHAINS=%s\n' "$ORIGINAL_KEYCHAINS" >> "$GITHUB_ENV"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/drift-certificate.p12" \
  -P "$CERTIFICATE_PASSWORD" -t cert -f pkcs12 -k "$KEYCHAIN_PATH" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" $ORIGINAL_KEYCHAINS
security default-keychain -d user -s "$KEYCHAIN_PATH"
```

Then run:

```bash
swift test
scripts/check-release-monotonic.sh --repository "$GITHUB_REPOSITORY" --output build/release/previous-release.json
make verify-release-artifacts CODESIGN_IDENTITY=Drift
scripts/check-release-monotonic.sh --repository "$GITHUB_REPOSITORY" --output build/release/previous-release.json
```

Always upload the three verified files as an Actions artifact named `drift-${RELEASE_VERSION}-verified`. Only when publish is requested, call `publish-github-release.sh` and then `verify-published-release.sh`.

Cleanup uses `if: always()`, restores `ORIGINAL_KEYCHAINS` and `ORIGINAL_DEFAULT_KEYCHAIN` when present, then deletes the `.p12` and temporary Keychain. It must not print secret values, list private keys, or upload the build scratch directories.

- [ ] **Step 5: Run workflow tests and inspect the diff for secret leaks**

Run:

```bash
swift test --filter ReleaseWorkflowTests
git diff --check
grep -nE 'set -x|--clobber|echo .*SPARKLE_PRIVATE_KEY|cat .*p12' .github/workflows/release.yml scripts/*.sh && exit 1 || true
```

Expected: tests PASS and grep returns no forbidden matches.

- [ ] **Step 6: Commit the workflow**

```bash
git add .github/workflows/release.yml Tests/DriftAppTests/ReleaseWorkflowTests.swift
git commit -m "ci: add self-signed release workflow"
```

---

### Task 9: Document operations and complete local/CI dry-runs

**Files:**
- Create: `docs/releasing.md`
- Modify: `README.md:30-101`
- Modify: `README.ko.md:30-101`
- Modify: `Tests/DriftAppTests/AppBundleTests.swift:18-30` only if public documentation requires a source-plist assertion change; production release bundle assertions remain in release tests.

**Interfaces:**
- Consumes: completed local and CI pipeline.
- Produces: operator instructions for versioning, selected-identity export, GitHub secrets, dry-run, publication, recovery, Gatekeeper, and future notarization.
- Produces: evidence from a real local dry-run and a manual GitHub Actions dry-run, but no `v0.1.0` Release.

- [ ] **Step 1: Add the release runbook before running credential-backed operations**

Document these exact sections in `docs/releasing.md`:

1. **Trust model** — self-signed `Drift`, fixed Sparkle Ed25519 key, Gatekeeper warning, no notarization.
2. **Version bump** — edit only `release/version.json`, run `scripts/sync-release-version.sh`, then `make release-metadata-check`.
3. **Local prerequisites** — `make check-local-certificate`, `make check-eddsa-key`, `gh auth status`.
4. **Certificate export** — in Keychain Access, select only the `Drift` certificate together with its private key, export `Drift.p12`, set a temporary strong password, and do not use `security export -t identities` because that may export unrelated identities.
5. **Secret registration** — pipe values without printing them:

```bash
base64 < /secure/path/Drift.p12 | gh secret set DRIFT_CERTIFICATE_BASE64
read -s 'P12_PASSWORD?Drift.p12 password: '; printf '%s' "$P12_PASSWORD" | gh secret set DRIFT_CERTIFICATE_PASSWORD; unset P12_PASSWORD
security find-generic-password \
  -s https://sparkle-project.org \
  -a com.woosublee.drift.sparkle.ed25519 \
  -w | gh secret set SPARKLE_PRIVATE_KEY
```

6. **Dry-run** — `scripts/release-local.sh`, then manual Actions dispatch with `publish=false`.
7. **Tag preparation** — after approval only: verify the approved release commit with `git rev-parse HEAD`, then run `git tag -a v0.1.0 -m 'Drift 0.1.0' HEAD` and push that tag.
8. **Publication** — tag push or tag-ref manual dispatch; no script creates the tag.
9. **Partial recovery** — only matching checksums resume; mismatches require investigation.
10. **Key continuity and future notarization** — retain protected backups; Developer ID is a separate future workflow.

Update both READMEs to say production releases use Sparkle, link the runbook, and retain the development-build no-feed statement.

- [ ] **Step 2: Run the complete test suite from a clean Swift build**

Run:

```bash
swift package clean
swift test
make -s release-metadata-check
git diff --check
```

Expected: all tests PASS and no formatting errors.

- [ ] **Step 3: Run the real local credential-backed dry-run**

Run:

```bash
make check-local-certificate
make check-eddsa-key
scripts/release-local.sh
```

Expected evidence:

- `build/release/Drift.app` contains `arm64 x86_64`.
- `build/release/Drift-0.1.0.dmg`, `appcast.xml`, and `release-provenance.json` exist.
- app/DMG code signatures pass.
- Sparkle key match and `sign_update --verify` pass.
- provenance parity passes.
- output ends with `Dry-run complete; no tag or GitHub Release was created`.
- `git tag --list v0.1.0` and `gh release view v0.1.0` show that no first Release was created by the dry-run.

- [ ] **Step 4: Register GitHub secrets without retaining the exported certificate**

After exporting only the `Drift` identity through Keychain Access, execute the three runbook commands. Then verify names only:

```bash
gh secret list | grep -E '^(DRIFT_CERTIFICATE_BASE64|DRIFT_CERTIFICATE_PASSWORD|SPARKLE_PRIVATE_KEY)[[:space:]]'
```

Expected: exactly three names. Delete the exported `.p12` securely from its temporary location after registration; do not add it to shell history, Git, or build output.

- [ ] **Step 5: Run and verify the GitHub Actions dry-run**

Run:

```bash
gh workflow run release.yml --ref main -f publish=false
run_id="$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --exit-status
gh run download "$run_id" --name 'drift-0.1.0-verified' --dir /tmp/drift-ci-dry-run
```

Verify the downloaded directory contains exactly:

```text
Drift-0.1.0.dmg
appcast.xml
release-provenance.json
```

Also run:

```bash
gh release view v0.1.0 >/dev/null 2>&1 && exit 1 || true
```

Expected: workflow succeeds and no GitHub Release exists.

- [ ] **Step 6: Commit documentation and any final test-only corrections**

```bash
git add docs/releasing.md README.md README.ko.md Tests/DriftAppTests/AppBundleTests.swift
git commit -m "docs: add self-signed release runbook"
```

- [ ] **Step 7: Stop before the first public release and request approval**

Present:

- full `swift test` result
- local dry-run result
- CI dry-run URL and result
- artifact names and SHA-256 values
- confirmation that `v0.1.0` tag/Release do not exist
- confirmation that secret values were not logged

Do not create or push `v0.1.0`, do not run `scripts/release-local.sh --publish`, and do not dispatch `publish=true` until the user separately approves the public release.
