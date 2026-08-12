#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 -r -- "usage: $0 {validate|version|build|tag|dmg-name|dmg-path|appcast-path|provenance-path|feed-url|download-url|shell|json}"
    exit 2
fi

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

case "$1" in
    validate) ;;
    version) print -r -- "$RELEASE_VERSION" ;;
    build) print -r -- "$RELEASE_BUILD" ;;
    tag) print -r -- "$RELEASE_TAG" ;;
    dmg-name) print -r -- "$RELEASE_DMG_NAME" ;;
    dmg-path) print -r -- "$RELEASE_DMG_PATH" ;;
    appcast-path) print -r -- "$RELEASE_APPCAST_PATH" ;;
    provenance-path) print -r -- "$RELEASE_PROVENANCE_PATH" ;;
    feed-url) print -r -- "$RELEASE_FEED_URL" ;;
    download-url) print -r -- "$RELEASE_DOWNLOAD_URL" ;;
    shell)
        printf "RELEASE_VERSION='%s'\n" "$RELEASE_VERSION"
        printf "RELEASE_BUILD='%s'\n" "$RELEASE_BUILD"
        printf "RELEASE_TAG='%s'\n" "$RELEASE_TAG"
        printf "RELEASE_DMG_NAME='%s'\n" "$RELEASE_DMG_NAME"
        printf "RELEASE_DMG_PATH='%s'\n" "$RELEASE_DMG_PATH"
        printf "RELEASE_APPCAST_PATH='%s'\n" "$RELEASE_APPCAST_PATH"
        printf "RELEASE_PROVENANCE_PATH='%s'\n" "$RELEASE_PROVENANCE_PATH"
        printf "RELEASE_FEED_URL='%s'\n" "$RELEASE_FEED_URL"
        printf "RELEASE_DOWNLOAD_URL='%s'\n" "$RELEASE_DOWNLOAD_URL"
        ;;
    json)
        python3 - \
            "$RELEASE_VERSION" \
            "$RELEASE_BUILD" \
            "$RELEASE_TAG" \
            "$RELEASE_DMG_NAME" \
            "$RELEASE_DMG_PATH" \
            "$RELEASE_APPCAST_PATH" \
            "$RELEASE_PROVENANCE_PATH" \
            "$RELEASE_FEED_URL" \
            "$RELEASE_DOWNLOAD_URL" <<'PY'
import json
import sys

(
    version,
    build,
    tag,
    dmg_name,
    dmg_path,
    appcast_path,
    provenance_path,
    feed_url,
    download_url,
) = sys.argv[1:]
print(json.dumps({
    "version": version,
    "build": int(build),
    "tag": tag,
    "dmgName": dmg_name,
    "dmgPath": dmg_path,
    "appcastPath": appcast_path,
    "provenancePath": provenance_path,
    "feedURL": feed_url,
    "downloadURL": download_url,
}, separators=(",", ":")))
PY
        ;;
    *)
        print -u2 -r -- "field must be validate, version, build, tag, dmg-name, dmg-path, appcast-path, provenance-path, feed-url, download-url, shell, or json"
        exit 2
        ;;
esac
