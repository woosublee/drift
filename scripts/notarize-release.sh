#!/bin/zsh
set -euo pipefail

: "${XCRUN:=xcrun}"
: "${DITTO:=ditto}"
: "${NOTARY_KEYCHAIN_PROFILE:=drift-notary}"
: "${NOTARY_TIMEOUT:=30m}"

usage() {
    print -u2 -r -- "usage: $0 --check | <path-to-app-or-dmg>"
    exit 2
}

(( $# == 1 )) || usage

# CI passes an App Store Connect API key; local releases use a notarytool Keychain profile.
if [[ -n "${NOTARY_API_KEY_PATH:-}" ]]; then
    [[ -f "$NOTARY_API_KEY_PATH" ]] || { print -u2 -r -- "ERROR: NOTARY_API_KEY_PATH does not exist"; exit 1; }
    [[ -n "${NOTARY_API_KEY_ID:-}" ]] || { print -u2 -r -- "ERROR: NOTARY_API_KEY_ID is required with NOTARY_API_KEY_PATH"; exit 1; }
    [[ -n "${NOTARY_API_ISSUER_ID:-}" ]] || { print -u2 -r -- "ERROR: NOTARY_API_ISSUER_ID is required with NOTARY_API_KEY_PATH"; exit 1; }
    credentials=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
else
    credentials=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
fi

if [[ "$1" == "--check" ]]; then
    "$XCRUN" notarytool history "${credentials[@]}" >/dev/null || {
        print -u2 -r -- "ERROR: notarytool credentials are not usable"
        exit 1
    }
    print -r -- "Notary credentials work"
    exit 0
fi

target="${1:A}"
case "$target" in
    *.app) [[ -d "$target" ]] || { print -u2 -r -- "ERROR: app does not exist: $target"; exit 1; } ;;
    *.dmg) [[ -f "$target" ]] || { print -u2 -r -- "ERROR: DMG does not exist: $target"; exit 1; } ;;
    *) usage ;;
esac

workdir="$(mktemp -d "${TMPDIR:-/tmp}/drift-notarize.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

submission="$target"
if [[ "$target" == *.app ]]; then
    submission="$workdir/${target:t:r}.zip"
    "$DITTO" -c -k --keepParent "$target" "$submission"
fi

result="$workdir/submission.json"
"$XCRUN" notarytool submit "$submission" "${credentials[@]}" \
    --wait --timeout "$NOTARY_TIMEOUT" --output-format json > "$result" || true

read -r submission_id submission_status <<EOF
$(python3 - "$result" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding='utf-8') as handle:
        value = json.load(handle)
except (OSError, ValueError):
    raise SystemExit('ERROR: notarytool did not return a JSON submission result')
print(value.get('id') or '-', value.get('status') or '-')
PY
)
EOF

if [[ "$submission_status" != "Accepted" ]]; then
    print -u2 -r -- "ERROR: notarization of ${target:t} finished with status $submission_status"
    if [[ "$submission_id" != "-" ]]; then
        "$XCRUN" notarytool log "$submission_id" "${credentials[@]}" >&2 || true
    fi
    exit 1
fi

"$XCRUN" stapler staple "$target"
"$XCRUN" stapler validate "$target"
print -r -- "Notarized and stapled ${target:t} ($submission_id)"
