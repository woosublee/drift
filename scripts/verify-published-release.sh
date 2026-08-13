#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${GH:=gh}"
: "${CURL:=curl}"
: "${SHASUM:=shasum}"
: "${VERIFY_RELEASE_ARTIFACTS:=$script_dir/verify-release-artifacts.sh}"
: "${SLEEP:=sleep}"

usage() {
    print -u2 -r -- "usage: $0 --repository OWNER/REPO --tag TAG"
    exit 2
}

repository=""
tag=""
while (( $# > 0 )); do
    case "$1" in
        --repository)
            [[ -z "$repository" && $# -ge 2 ]] || usage
            repository="$2"
            shift 2
            ;;
        --tag)
            [[ -z "$tag" && $# -ge 2 ]] || usage
            tag="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done
[[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    print -u2 -r -- "ERROR: repository must use OWNER/REPO format"
    exit 2
}
[[ -n "$tag" ]] || usage

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"
[[ "$tag" == "$RELEASE_TAG" ]] || {
    print -u2 -r -- "ERROR: supplied tag must equal $RELEASE_TAG"
    exit 1
}

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/drift-published-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
assets=("$RELEASE_DMG_NAME" appcast.xml release-provenance.json)
for asset in "${assets[@]}"; do
    "$GH" release download "$tag" --repo "$repository" --pattern "$asset" --dir "$temporary_directory"
    [[ -f "$temporary_directory/$asset" ]] || {
        print -u2 -r -- "ERROR: tagged Release is missing canonical asset: $asset"
        exit 1
    }
done

sha256() {
    "$SHASUM" -a 256 "$1" | awk '{print tolower($1)}'
}
provenance="$temporary_directory/release-provenance.json"
expected_checksums="$(python3 - "$provenance" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    value = json.load(handle)
try:
    artifacts = value['artifacts']
    print(artifacts['dmg']['name'], artifacts['dmg']['sha256'])
    print(artifacts['appcast']['name'], artifacts['appcast']['sha256'])
except (KeyError, TypeError):
    raise SystemExit('ERROR: provenance is missing canonical artifact checksums')
PY
)"
while IFS=' ' read -r name checksum; do
    [[ -n "$name$checksum" ]] || continue
    [[ "$(sha256 "$temporary_directory/$name")" == "$checksum" ]] || {
        print -u2 -r -- "ERROR: published asset checksum mismatch: $name"
        exit 1
    }
done <<< "$expected_checksums"

"$VERIFY_RELEASE_ARTIFACTS" \
    --source-plist Info.plist \
    --app build/release/Drift.app \
    --dmg "$temporary_directory/$RELEASE_DMG_NAME" \
    --appcast "$temporary_directory/appcast.xml" \
    --provenance "$provenance"

tagged_appcast_sha256="$(sha256 "$temporary_directory/appcast.xml")"
latest_url="https://github.com/$repository/releases/latest/download/appcast.xml"
retry_delays=(5 10 20 30)
for delay in "${retry_delays[@]}"; do
    latest_appcast="$temporary_directory/latest-appcast.xml"
    rm -f "$latest_appcast"
    if "$CURL" --fail --location --silent --show-error --output "$latest_appcast" "$latest_url" &&
        [[ "$(sha256 "$latest_appcast")" == "$tagged_appcast_sha256" ]]; then
        print -r -- "Published release verification complete: $tag"
        exit 0
    fi
    "$SLEEP" "$delay"
done

print -u2 -r -- "ERROR: latest appcast checksum did not match tagged appcast after four attempts"
exit 1
