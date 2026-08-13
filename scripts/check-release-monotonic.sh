#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${GH:=gh}"

usage() {
    print -u2 -r -- "usage: $0 --repository OWNER/REPO [--previous-appcast FILE] [--exclude-tag TAG] --output FILE"
    exit 2
}

repository=""
previous_appcast=""
exclude_tag=""
output=""

while (( $# > 0 )); do
    case "$1" in
        --repository)
            (( $# >= 2 )) || usage
            repository="$2"
            shift 2
            ;;
        --previous-appcast)
            (( $# >= 2 )) || usage
            previous_appcast="$2"
            shift 2
            ;;
        --exclude-tag)
            (( $# >= 2 )) || usage
            exclude_tag="$2"
            shift 2
            ;;
        --output)
            (( $# >= 2 )) || usage
            output="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

[[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    print -u2 -r -- "ERROR: repository must use OWNER/REPO format"
    exit 2
}
[[ -n "$output" ]] || usage

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

output="${output:A}"
mkdir -p "${output:h}"
temporary_output="$(mktemp "${output:h}/.${output:t}.XXXXXX")"
trap 'rm -f "$temporary_output"' EXIT

write_previous() {
    local source="$1"
    local appcast="$2"
    local expected_tag="${3:-}"

    local previous_version previous_build previous_url previous_dmg_name previous_tag
    previous_build="$(release_appcast_extract_enclosure_version "$appcast")" || exit 1
    previous_url="$(release_appcast_extract_enclosure_url "$appcast")" || exit 1
    previous_version="$(release_appcast_extract_item_short_version "$appcast")" || exit 1
    release_is_stable_semver "$previous_version" || {
        print -u2 -r -- "ERROR: previous appcast version must use stable SemVer x.y.z"
        exit 1
    }
    release_is_positive_int64 "$previous_build" || {
        print -u2 -r -- "ERROR: previous appcast build must be a positive 64-bit integer"
        exit 1
    }
    previous_dmg_name="Drift-$previous_version.dmg"
    [[ "$previous_url" == *"/$previous_dmg_name"* ]] || {
        print -u2 -r -- "ERROR: appcast enclosure URL must name $previous_dmg_name"
        exit 1
    }
    previous_tag="v$previous_version"
    if [[ -n "$expected_tag" ]] && [[ "$previous_tag" != "$expected_tag" ]]; then
        print -u2 -r -- "ERROR: appcast tag $previous_tag does not match selected Release tag $expected_tag"
        exit 1
    fi
    if ! release_positive_integer_greater_than "$RELEASE_BUILD" "$previous_build"; then
        print -u2 -r -- "ERROR: current build $RELEASE_BUILD must be greater than previous build $previous_build"
        exit 1
    fi
    python3 - "$temporary_output" "$source" "$previous_version" "$previous_build" "$previous_tag" "$previous_dmg_name" <<'PY'
import json
import sys

output, source, version, build, tag, dmg_name = sys.argv[1:]
with open(output, 'w', encoding='utf-8', newline='\n') as handle:
    json.dump({
        'source': source,
        'previous': {
            'version': version,
            'build': int(build),
            'tag': tag,
            'dmgName': dmg_name,
        },
    }, handle, sort_keys=True, separators=(',', ':'))
    handle.write('\n')
PY
}

if [[ -n "$previous_appcast" ]]; then
    [[ -f "$previous_appcast" ]] || {
        print -u2 -r -- "ERROR: previous appcast does not exist: $previous_appcast"
        exit 1
    }
    write_previous "explicit-previous-appcast" "$previous_appcast"
else
    releases="$($GH release list --repo "$repository" --exclude-drafts --exclude-pre-releases --json tagName,publishedAt)" || exit 1
    selected_tag="$(python3 - "$releases" "$exclude_tag" <<'PY'
import json
import sys

try:
    releases = json.loads(sys.argv[1])
except json.JSONDecodeError as error:
    raise SystemExit(f'ERROR: could not parse GitHub releases: {error}')
exclude = sys.argv[2]
stable = [
    release for release in releases
    if isinstance(release, dict)
    and isinstance(release.get('tagName'), str)
    and isinstance(release.get('publishedAt'), str)
    and release['tagName'] != exclude
]
stable.sort(key=lambda release: release['publishedAt'], reverse=True)
if stable:
    print(stable[0]['tagName'])
PY
)" || exit 1

    if [[ -z "$selected_tag" ]]; then
        python3 - "$temporary_output" <<'PY'
import json
import sys

with open(sys.argv[1], 'w', encoding='utf-8', newline='\n') as handle:
    json.dump({'source': 'no-previous-release', 'previous': None}, handle, sort_keys=True, separators=(',', ':'))
    handle.write('\n')
PY
    else
        download_directory="$(mktemp -d "${TMPDIR:-/tmp}/drift-previous-appcast.XXXXXX")"
        trap 'rm -f "$temporary_output"; rm -rf "$download_directory"' EXIT
        "$GH" release download "$selected_tag" --repo "$repository" --pattern appcast.xml --dir "$download_directory"
        downloaded_appcast="$download_directory/appcast.xml"
        [[ -f "$downloaded_appcast" ]] || {
            print -u2 -r -- "ERROR: selected Release $selected_tag does not contain appcast.xml"
            exit 1
        }
        write_previous "github-release-appcast" "$downloaded_appcast" "$selected_tag"
    fi
fi

release_atomic_replace "$temporary_output" "$output"
trap - EXIT
