# Releasing Drift

This runbook covers the self-signed stable-release process. It deliberately separates evidence-gathering dry-runs from public publication: no local script creates a tag, and the first public release requires separate approval.

## 1. Trust model

Production `Drift` (`com.woosublee.drift`) is signed with the existing self-signed `Drift` identity. Sparkle uses the fixed Ed25519 public key in the production `Info.plist` to verify updates from the stable feed:

`https://github.com/woosublee/drift/releases/latest/download/appcast.xml`

Because the app is self-signed rather than Developer ID-signed and notarized, Gatekeeper may warn users before they open it. Explain that warning honestly; do not describe the app as notarized or bypass Gatekeeper programmatically. Development builds are intentionally separate `Drift Dev` bundles and contain neither `SUFeedURL` nor `SUPublicEDKey`.

## 2. Version bump

For a release, edit only `release/version.json`. Do not override a version, build number, tag, DMG path, or bundle identifier through Make or the environment. Sync the production plist and verify the metadata:

```bash
scripts/sync-release-version.sh
make release-metadata-check
```

The first release is marketing version `0.1.0`, build `1`, and tag `v0.1.0`.

## 3. Local prerequisites

Before any credential-backed release work, confirm the expected local certificate, Sparkle key, and GitHub CLI authentication:

```bash
make check-local-certificate
make check-eddsa-key
gh auth status
```

The release build must remain universal (`arm64` and `x86_64`) and targets macOS 13.0 or later.

## 4. Certificate export

Use **Keychain Access** to export the CI signing certificate. Select only the `Drift` certificate together with its private key, export it as `Drift.p12`, and set a temporary strong export password.

Do **not** use `security export -t identities`: it can export unrelated identities. Keep the `.p12` in a secure temporary location, do not add it to Git, shell history, build output, or artifacts, and securely delete it after GitHub secret registration.

## 5. Secret registration

Register the certificate, its temporary export password, and Sparkle private key without printing the values. Replace `/secure/path/Drift.p12` with the temporary export location, and run these commands only in a trusted local shell:

```bash
base64 < /secure/path/Drift.p12 | gh secret set DRIFT_CERTIFICATE_BASE64
read -s 'P12_PASSWORD?Drift.p12 password: '; printf '%s' "$P12_PASSWORD" | gh secret set DRIFT_CERTIFICATE_PASSWORD; unset P12_PASSWORD
security find-generic-password \
  -s https://sparkle-project.org \
  -a com.woosublee.drift.sparkle.ed25519 \
  -w | gh secret set SPARKLE_PRIVATE_KEY
```

The final command streams the private key directly to GitHub and must never be redirected to a file or terminal. After registration, verify secret *names only* and securely delete the temporary `.p12`:

```bash
gh secret list | grep -E '^(DRIFT_CERTIFICATE_BASE64|DRIFT_CERTIFICATE_PASSWORD|SPARKLE_PRIVATE_KEY)[[:space:]]'
```

## 6. Dry-run

Start with the local dry-run, which builds and verifies the canonical artifacts but does not create a tag or GitHub Release:

```bash
scripts/release-local.sh
```

Confirm `build/release/Drift.app` contains `arm64` and `x86_64`, and that `build/release/Drift-0.1.0.dmg`, `appcast.xml`, and `release-provenance.json` exist. The run checks app and DMG signatures, Sparkle key continuity and `sign_update --verify`, and provenance parity. It must end with:

```text
Dry-run complete; no tag or GitHub Release was created
```

Then manually dispatch the **Self-signed Release** workflow with `publish=false`. Download its `drift-0.1.0-verified` artifact and verify it contains exactly `Drift-0.1.0.dmg`, `appcast.xml`, and `release-provenance.json`. Confirm that neither `git tag --list v0.1.0` nor `gh release view v0.1.0` finds a public release before seeking publication approval.

## 7. Tag preparation

Only after release approval, verify the approved release commit and create the annotated tag at that exact `HEAD`:

```bash
git rev-parse HEAD
git tag -a v0.1.0 -m 'Drift 0.1.0' HEAD
git push origin v0.1.0
```

Do not move or recreate the tag. The local release script does not create tags.

## 8. Publication

Publication occurs from a tag push or a manual workflow dispatch against the canonical tag reference. The production workflow publishes only the three canonical assets:

- `Drift-${RELEASE_VERSION}.dmg`
- `appcast.xml`
- `release-provenance.json`

Use `publish=false` for verification-only workflow dispatches. Use publication only after the tag, local dry-run, CI dry-run, and approval are all complete; no script creates the tag for you.

## 9. Partial recovery

If publication is interrupted, resume only when every existing uploaded asset has the checksum of the locally verified canonical artifact. A matching checksum may be resumed; any mismatch requires investigation before retrying. Never overwrite or replace an asset merely to force a release through.

## 10. Key continuity and future notarization

Retain protected backups of the self-signed certificate/private key, Sparkle key, and recovery information. The Sparkle Ed25519 key is a continuity commitment: replacing it would strand existing installations from future updates.

Developer ID signing and notarization are a separate future workflow. Do not treat the self-signed release flow as notarized, and do not add Developer ID credentials or notarization steps to this process without a separately approved migration plan.
