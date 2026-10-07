#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
: "${HDIUTIL:=hdiutil}"
: "${CODESIGN:=codesign}"
: "${DITTO:=ditto}"
: "${NOTARIZE:=$script_dir/notarize-release.sh}"

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
eval "$("$script_dir/resolve-release-version.sh" shell)"

app="$repo_root/build/release/Drift.app"
dmg="$repo_root/$RELEASE_DMG_PATH"
staging="$(mktemp -d "${TMPDIR:-/tmp}/drift-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

# Staple the app itself so a copy dragged out of the DMG passes Gatekeeper offline.
"$NOTARIZE" "$app"
"$DITTO" --norsrc --noextattr "$app" "$staging/Drift.app"
"$script_dir/verify-bundle-signing-xattrs.sh" "$staging/Drift.app"
"$CODESIGN" --verify --deep --strict --verbose=2 "$staging/Drift.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
"$HDIUTIL" create -volname Drift -srcfolder "$staging" -ov -format UDZO "$dmg"
"$CODESIGN" --force --timestamp --sign "${CODESIGN_IDENTITY:-$RELEASE_CODESIGN_IDENTITY}" "$dmg"
"$CODESIGN" --verify --strict --verbose=2 "$dmg"
# Stapling rewrites the DMG, so the Sparkle appcast must be generated after this step.
"$NOTARIZE" "$dmg"
"$CODESIGN" --verify --strict --verbose=2 "$dmg"
