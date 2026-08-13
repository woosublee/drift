#!/bin/zsh
set -euo pipefail

if (( $# > 1 )); then
    print -u2 -r -- "usage: $0 [--check]"
    exit 2
fi
if (( $# == 1 )) && [[ "$1" != "--check" ]]; then
    print -u2 -r -- "usage: $0 [--check]"
    exit 2
fi

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
plist="$repo_root/Info.plist"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

[[ -f "$plist" ]] || release_fail "Info.plist does not exist"
plist_version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
plist_build="$(plutil -extract CFBundleVersion raw "$plist")"

mismatch=0
if [[ "$plist_version" != "$RELEASE_VERSION" ]]; then
    print -u2 -r -- "ERROR: Info.plist version mismatch: expected $RELEASE_VERSION, found $plist_version"
    mismatch=1
fi
if [[ "$plist_build" != "$RELEASE_BUILD" ]]; then
    print -u2 -r -- "ERROR: Info.plist build mismatch: expected $RELEASE_BUILD, found $plist_build"
    mismatch=1
fi

if (( $# == 1 )); then
    (( mismatch == 0 )) && exit 0
    exit 1
fi

if (( mismatch == 0 )); then
    exit 0
fi

temporary_plist="$(mktemp "${plist}.XXXXXX")"
trap 'rm -f "$temporary_plist"' EXIT
cp "$plist" "$temporary_plist"
plutil -replace CFBundleShortVersionString -string "$RELEASE_VERSION" "$temporary_plist"
plutil -replace CFBundleVersion -string "$RELEASE_BUILD" "$temporary_plist"
plutil -lint "$temporary_plist" >/dev/null
[[ "$(plutil -extract CFBundleShortVersionString raw "$temporary_plist")" == "$RELEASE_VERSION" ]] || release_fail "temporary Info.plist version validation failed"
[[ "$(plutil -extract CFBundleVersion raw "$temporary_plist")" == "$RELEASE_BUILD" ]] || release_fail "temporary Info.plist build validation failed"
release_atomic_replace "$temporary_plist" "$plist"
trap - EXIT
