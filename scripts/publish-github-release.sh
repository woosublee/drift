#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${GH:=gh}"
: "${GIT:=git}"
: "${SHASUM:=shasum}"

usage() {
    print -u2 -r -- "usage: $0 --repository OWNER/REPO --tag TAG --notes FILE"
    exit 2
}

repository=""
tag=""
notes=""
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
        --notes)
            [[ -z "$notes" && $# -ge 2 ]] || usage
            notes="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done
[[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    print -u2 -r -- "ERROR: repository must use OWNER/REPO format"
    exit 2
}
[[ -n "$tag" && -n "$notes" ]] || usage

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

[[ "$tag" == "$RELEASE_TAG" ]] || {
    print -u2 -r -- "ERROR: supplied tag must equal $RELEASE_TAG"
    exit 1
}
[[ -f "$notes" ]] || {
    print -u2 -r -- "ERROR: release notes do not exist: $notes"
    exit 1
}

head_commit="$($GIT rev-parse HEAD)"
[[ "$($GIT cat-file -t "refs/tags/$tag")" == "tag" ]] || {
    print -u2 -r -- "ERROR: release tag must be annotated"
    exit 1
}
[[ "$($GIT rev-list -n 1 "refs/tags/$tag")" == "$head_commit" ]] || {
    print -u2 -r -- "ERROR: release tag must resolve to HEAD"
    exit 1
}
remote_tags="$($GIT ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")"
remote_peeled_commit="$(print -r -- "$remote_tags" | grep -E "[[:space:]]refs/tags/${tag//./\\.}\\^\\{\\}$" | awk '{print $1}')"
[[ "$remote_peeled_commit" == "$head_commit" ]] || {
    print -u2 -r -- "ERROR: origin release tag must be annotated and resolve to HEAD"
    exit 1
}

release_json=""
if ! release_json="$($GH release view "$tag" --repo "$repository" --json isDraft,isPrerelease,name 2>&1)"; then
    [[ "$release_json" == *"release not found"* ]] || {
        print -u2 -r -- "ERROR: could not determine whether GitHub Release exists: $release_json"
        exit 1
    }
    "$GH" release create "$tag" --repo "$repository" --verify-tag --latest \
        --title "Drift $RELEASE_VERSION" --notes-file "$notes"
else
    python3 - "$release_json" "Drift $RELEASE_VERSION" <<'PY'
import json
import sys

try:
    release = json.loads(sys.argv[1])
except json.JSONDecodeError as error:
    raise SystemExit(f"ERROR: could not parse existing release: {error}")
expected_title = sys.argv[2]
if not isinstance(release, dict):
    raise SystemExit("ERROR: existing release response is invalid")
if release.get("isDraft") is not False:
    raise SystemExit("ERROR: existing release must not be a draft")
if release.get("isPrerelease") is not False:
    raise SystemExit("ERROR: existing release must not be a prerelease")
if release.get("name") != expected_title:
    raise SystemExit(f"ERROR: existing release title must equal {expected_title}")
PY
fi

sha256() {
    "$SHASUM" -a 256 "$1" | awk '{print tolower($1)}'
}

assets=(
    "$RELEASE_DMG_PATH"
    "$RELEASE_APPCAST_PATH"
    "$RELEASE_PROVENANCE_PATH"
)
for asset in "${assets[@]}"; do
    [[ -f "$asset" ]] || {
        print -u2 -r -- "ERROR: canonical release asset does not exist: $asset"
        exit 1
    }
done

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/drift-release-publish.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
for asset in "${assets[@]}"; do
    name="${asset:t}"
    downloaded="$temporary_directory/$name"
    rm -f "$downloaded"
    if "$GH" release download "$tag" --repo "$repository" --pattern "$name" --dir "$temporary_directory"; then
        [[ -f "$downloaded" ]] || {
            print -u2 -r -- "ERROR: GitHub Release download did not produce $name"
            exit 1
        }
        [[ "$(sha256 "$downloaded")" == "$(sha256 "$asset")" ]] || {
            print -u2 -r -- "ERROR: existing asset checksum mismatch: $name"
            exit 1
        }
        print -r -- "Existing asset matches canonical checksum: $name"
    else
        "$GH" release upload "$tag" --repo "$repository" "$asset"
        print -r -- "Uploaded missing canonical asset: $name"
    fi
done

print -r -- "GitHub Release publication complete: $tag"
