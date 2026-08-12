#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${GIT:=git}"
: "${MAKE:=make}"
: "${MONOTONICITY_CHECKER:=$script_dir/check-release-monotonic.sh}"
: "${GH:=gh}"

usage() {
    print -u2 -r -- "usage: $0 [--publish] [--previous-appcast FILE]"
    exit 2
}

publish=0
previous_appcast=""
while (( $# > 0 )); do
    case "$1" in
        --publish)
            (( publish == 0 )) || usage
            publish=1
            shift
            ;;
        --previous-appcast)
            [[ -z "$previous_appcast" && $# -ge 2 ]] || usage
            previous_appcast="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

[[ -z "$($GIT status --porcelain)" ]] || {
    print -u2 -r -- "ERROR: working tree must be clean"
    exit 1
}
"$MAKE" release-metadata-check
repository_url="$($GIT ls-remote --get-url origin)"
case "$repository_url" in
    github.com:woosublee/drift.git|git@github.com:woosublee/drift.git|https://github.com/woosublee/drift.git)
        ;;
    *)
        print -u2 -r -- "ERROR: origin must identify woosublee/drift"
        exit 1
        ;;
esac
"$MAKE" test
"$GH" auth status >/dev/null
"$MAKE" check-local-certificate
"$MAKE" check-eddsa-key

monotonicity_output="build/release/previous-release.json"
monotonicity_arguments=(--repository woosublee/drift --output "$monotonicity_output" --exclude-tag "$RELEASE_TAG")
if [[ -n "$previous_appcast" ]]; then
    monotonicity_arguments+=(--previous-appcast "$previous_appcast")
fi
"$MONOTONICITY_CHECKER" "${monotonicity_arguments[@]}"
"$MAKE" verify-release-artifacts
"$MONOTONICITY_CHECKER" "${monotonicity_arguments[@]}"

if (( publish == 0 )); then
    print -r -- "Dry-run complete; no tag or GitHub Release was created"
    exit 0
fi

"$script_dir/publish-github-release.sh" \
    --repository woosublee/drift \
    --tag "$RELEASE_TAG" \
    --notes "${RELEASE_NOTES_FILE:-release/notes.md}"
