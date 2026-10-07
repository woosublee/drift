# Releasing Drift

This runbook covers the Developer ID–signed, notarized stable-release process. It deliberately separates evidence-gathering dry-runs from public publication: no local script creates a tag, and the first public release requires separate approval.

## 1. Trust model

Production `Drift` (`com.woosublee.drift`) is signed with `Developer ID Application: Woosub Lee (2L6ZW98RCP)` using the hardened runtime and a secure timestamp. Release packaging notarizes and staples the app, builds the DMG from the stapled app, then signs, notarizes, and staples the DMG. The Sparkle appcast is generated only after that, so its EdDSA signature and length describe the final stapled DMG.

Sparkle uses the fixed Ed25519 public key in the production `Info.plist` to verify updates from the stable feed:

`https://github.com/woosublee/drift/releases/latest/download/appcast.xml`

Sparkle accepts an update when its EdDSA signature is valid and the new app has a valid code signature, so it permits a change of code-signing identity as long as the EdDSA key stays the same. That is what allowed the move from the self-signed `Drift` identity (0.1.6 and earlier) to Developer ID. **Never change the EdDSA key and the code-signing identity in the same release.** Because the designated requirement changed, users who update from a self-signed release have to grant Accessibility once more; the in-app permission guide covers this.

Development builds are intentionally separate `Drift Dev` bundles and contain neither `SUFeedURL` nor `SUPublicEDKey`.

## 2. Version bump

For a release, edit only `release/version.json`. Do not override a version, build number, tag, DMG path, or bundle identifier through Make or the environment. Sync the production plist and verify the metadata:

```bash
scripts/sync-release-version.sh
make release-metadata-check
```

The first release is marketing version `0.1.0`, build `1`, and tag `v0.1.0`.

## 3. Local prerequisites

Before any credential-backed release work, confirm the Developer ID identity, notarization credentials, Sparkle key, and GitHub CLI authentication:

```bash
make check-signing-identity
make check-notary-credentials
make check-eddsa-key
gh auth status
```

Local notarization uses the `drift-notary` notarytool Keychain profile (override with `NOTARY_KEYCHAIN_PROFILE`). Create it once with an App Store Connect API key (preferred) or an app-specific password:

```bash
xcrun notarytool store-credentials drift-notary \
  --key /secure/path/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
```

The release build must remain universal (`arm64` and `x86_64`) and targets macOS 13.0 or later.

## 4. Certificate and API key export

Use **Keychain Access** to export the CI signing certificate. Select only the `Developer ID Application: Woosub Lee (2L6ZW98RCP)` certificate together with its private key, export it as `DeveloperID.p12`, and set a temporary strong export password. The workflow downloads Apple's `Developer ID Certification Authority (G2)` intermediate itself.

Do **not** use `security export -t identities`: it can export unrelated identities. Keep the `.p12` and the App Store Connect `.p8` key in a secure temporary location, never add them to Git, shell history, build output, or artifacts, and securely delete the `.p12` after GitHub secret registration.

## 5. Secret registration

Register the certificate, its temporary export password, the notarization API key, and the Sparkle private key without printing the values. Run these commands only in a trusted local **zsh** shell:

```zsh
base64 < /secure/path/DeveloperID.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_BASE64
read -s 'P12_PASSWORD?DeveloperID.p12 password: '; printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD; unset P12_PASSWORD
base64 < /secure/path/AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_API_KEY_BASE64
gh secret set NOTARY_API_KEY_ID --body XXXXXXXXXX
gh secret set NOTARY_API_ISSUER_ID --body <issuer-uuid>
security find-generic-password \
  -s https://sparkle-project.org \
  -a com.woosublee.drift.sparkle.ed25519 \
  -w | gh secret set SPARKLE_PRIVATE_KEY
```

The final command streams the private key directly to GitHub and must never be redirected to a file or terminal. After registration, verify secret *names only*:

```bash
gh secret list | grep -E '^(DEVELOPER_ID_CERTIFICATE_BASE64|DEVELOPER_ID_CERTIFICATE_PASSWORD|NOTARY_API_KEY_BASE64|NOTARY_API_KEY_ID|NOTARY_API_ISSUER_ID|SPARKLE_PRIVATE_KEY)[[:space:]]'
```

## 6. Dry-run

Start with the local dry-run, which builds and verifies the canonical artifacts but does not create a tag or GitHub Release:

```bash
scripts/release-local.sh
```

Confirm `build/release/Drift.app` contains `arm64` and `x86_64`, and that `build/release/Drift-0.1.0.dmg`, `appcast.xml`, and `release-provenance.json` exist. The run checks app and DMG signatures, the Developer ID Team ID and secure timestamp, stapled notarization tickets, Gatekeeper assessment (`source=Notarized Developer ID`), Sparkle key continuity and `sign_update --verify`, and provenance parity. It must end with:

```text
Dry-run complete; no tag or GitHub Release was created
```

Then manually dispatch the **Notarized Release** workflow with `publish=false`. Download its `drift-0.1.0-verified` artifact and verify it contains exactly `Drift-0.1.0.dmg`, `appcast.xml`, and `release-provenance.json`. Confirm that neither `git tag --list v0.1.0` nor `gh release view v0.1.0` finds a public release before seeking publication approval.

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

## 10. Key continuity

Retain protected backups of the Developer ID certificate/private key, the App Store Connect API key, the Sparkle key, and recovery information. The Sparkle Ed25519 key is a continuity commitment: replacing it would strand existing installations from future updates. Rotate the Developer ID certificate and the Sparkle key only in separate releases, as described in the trust model.
