#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${CODESIGN:=codesign}"
: "${GIT:=git}"
: "${LIPO:=lipo}"
: "${OPENSSL:=openssl}"

usage() {
    print -u2 -r -- "usage: $0 --previous FILE"
    exit 2
}

previous=""
while (( $# > 0 )); do
    case "$1" in
        --previous)
            (( $# >= 2 )) || usage
            previous="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done
[[ -n "$previous" ]] || usage

cd "$repo_root"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"

previous="${previous:A}"
[[ -f "$previous" ]] || {
    print -u2 -r -- "ERROR: previous release metadata does not exist: $previous"
    exit 1
}

app="$repo_root/build/release/Drift.app"
app_info="$app/Contents/Info.plist"
dmg="$repo_root/$RELEASE_DMG_PATH"
appcast="$repo_root/$RELEASE_APPCAST_PATH"
output="$repo_root/$RELEASE_PROVENANCE_PATH"
[[ -d "$app" ]] || { print -u2 -r -- "ERROR: canonical release app does not exist: build/release/Drift.app"; exit 1; }
[[ -f "$app_info" ]] || { print -u2 -r -- "ERROR: canonical release app Info.plist does not exist"; exit 1; }
[[ -f "$dmg" ]] || { print -u2 -r -- "ERROR: canonical release DMG does not exist: $RELEASE_DMG_PATH"; exit 1; }
[[ -f "$appcast" ]] || { print -u2 -r -- "ERROR: canonical release appcast does not exist: $RELEASE_APPCAST_PATH"; exit 1; }

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$app_info")"
[[ "$bundle_identifier" == "com.woosublee.drift" ]] || {
    print -u2 -r -- "ERROR: release bundle identifier must be com.woosublee.drift"
    exit 1
}
feed_url="$(plutil -extract SUFeedURL raw "$app_info")"
[[ "$feed_url" == "$RELEASE_FEED_URL" ]] || {
    print -u2 -r -- "ERROR: release SUFeedURL must be $RELEASE_FEED_URL"
    exit 1
}
sparkle_public_key="$(plutil -extract SUPublicEDKey raw "$app_info")"

architectures="$("$LIPO" -archs "$app/Contents/MacOS/Drift" | tr ' ' '\n' | sort | paste -sd ',' -)"
[[ "$architectures" == "arm64,x86_64" ]] || {
    print -u2 -r -- "ERROR: release executable architectures must be exactly arm64 x86_64; found: ${architectures//,/ }"
    exit 1
}

certificate_directory="$(mktemp -d "${TMPDIR:-/tmp}/drift-provenance-cert.XXXXXX")"
trap 'rm -rf "$certificate_directory"' EXIT
certificate_prefix="$certificate_directory/certificate-"
"$CODESIGN" --extract-certificates "$certificate_prefix" "$app"
certificate="$certificate_prefix"0
[[ -f "$certificate" ]] || {
    print -u2 -r -- "ERROR: codesign did not extract a signing certificate"
    exit 1
}
certificate_common_name="$("$OPENSSL" x509 -inform DER -in "$certificate" -noout -subject -nameopt RFC2253 | python3 -c '
import re
import sys

subject = sys.stdin.read().strip()
match = re.fullmatch(r"subject=CN=([^,]+)", subject)
if not match:
    raise SystemExit("ERROR: signing certificate subject must contain only CN")
print(match.group(1))
')" || exit 1
certificate_sha256="$("$OPENSSL" x509 -inform DER -in "$certificate" -noout -fingerprint -sha256 | python3 -c '
import re
import sys

fingerprint = sys.stdin.read().strip()
match = re.fullmatch(r"sha256 Fingerprint=([0-9A-Fa-f:]+)", fingerprint)
if not match:
    raise SystemExit("ERROR: could not parse signing certificate SHA-256 fingerprint")
value = match.group(1).replace(":", "").upper()
if not re.fullmatch(r"[0-9A-F]{64}", value):
    raise SystemExit("ERROR: signing certificate SHA-256 fingerprint must contain 64 hex characters")
print(value)
')" || exit 1

commit="$($GIT rev-parse HEAD)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
    print -u2 -r -- "ERROR: Git HEAD must be a 40-character lowercase commit SHA"
    exit 1
}
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
    release_is_nonnegative_int64 "$SOURCE_DATE_EPOCH" || {
        print -u2 -r -- "ERROR: SOURCE_DATE_EPOCH must be a nonnegative 64-bit integer"
        exit 1
    }
    timestamp="$((SOURCE_DATE_EPOCH))"
else
    timestamp="$($GIT show -s --format=%ct HEAD)"
fi

mkdir -p "${output:h}"
temporary_output="$(mktemp "${output:h}/.${output:t}.XXXXXX")"
trap 'rm -rf "$certificate_directory"; rm -f "$temporary_output"' EXIT
python3 - \
    "$temporary_output" \
    "$previous" \
    "$RELEASE_VERSION" \
    "$RELEASE_BUILD" \
    "$RELEASE_TAG" \
    "$commit" \
    "$bundle_identifier" \
    "$architectures" \
    "$RELEASE_FEED_URL" \
    "$RELEASE_DOWNLOAD_URL" \
    "$certificate_common_name" \
    "$certificate_sha256" \
    "$sparkle_public_key" \
    "$dmg" \
    "$appcast" \
    "$timestamp" \
    "${GITHUB_RUN_ID:-}" <<'PY'
import datetime
import hashlib
import json
import os
import sys

(
    output,
    previous_path,
    version,
    build,
    tag,
    commit,
    bundle_identifier,
    architectures,
    feed_url,
    download_url,
    certificate_common_name,
    certificate_sha256,
    sparkle_public_key,
    dmg_path,
    appcast_path,
    timestamp,
    workflow_run_id,
) = sys.argv[1:]

with open(previous_path, encoding='utf-8') as handle:
    previous_metadata = json.load(handle)
if type(previous_metadata) is not dict or set(previous_metadata) != {'source', 'previous'}:
    raise SystemExit('ERROR: previous release metadata must contain exactly source and previous')
previous = previous_metadata['previous']
if previous is not None:
    if type(previous) is not dict or set(previous) != {'version', 'build', 'tag', 'dmgName'}:
        raise SystemExit('ERROR: previous release metadata has invalid previous value')

try:
    timestamp_value = int(timestamp)
except ValueError as error:
    raise SystemExit(f'ERROR: invalid build timestamp: {error}')
if timestamp_value < 0:
    raise SystemExit('ERROR: build timestamp must not be negative')
timestamp_iso = datetime.datetime.fromtimestamp(timestamp_value, tz=datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

def artifact(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return {
        'name': os.path.basename(path),
        'bytes': os.path.getsize(path),
        'sha256': digest.hexdigest(),
    }
workflow = int(workflow_run_id) if workflow_run_id else None
if workflow is not None and workflow <= 0:
    raise SystemExit('ERROR: GITHUB_RUN_ID must be a positive integer')

value = {
    'schemaVersion': 1,
    'release': {
        'version': version,
        'build': int(build),
        'tag': tag,
        'commit': commit,
        'repository': 'woosublee/drift',
        'bundleIdentifier': bundle_identifier,
        'architectures': architectures.split(','),
        'feedURL': feed_url,
        'downloadURL': download_url,
    },
    'signing': {
        'certificateCommonName': certificate_common_name,
        'certificateSHA256': certificate_sha256,
        'sparklePublicKey': sparkle_public_key,
    },
    'artifacts': {
        'dmg': artifact(dmg_path),
        'appcast': artifact(appcast_path),
    },
    'build': {
        'timestamp': timestamp_iso,
        'workflowRunID': workflow,
    },
    'previous': previous,
}
with open(output, 'w', encoding='utf-8', newline='\n') as handle:
    json.dump(value, handle, sort_keys=True, separators=(',', ':'))
    handle.write('\n')
PY
release_atomic_replace "$temporary_output" "$output"
trap - EXIT
rm -rf "$certificate_directory"
