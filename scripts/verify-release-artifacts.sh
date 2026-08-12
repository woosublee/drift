#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$script_dir:h"
: "${CODESIGN:=codesign}"
: "${GIT:=git}"
: "${HDIUTIL:=hdiutil}"
: "${LIPO:=lipo}"
: "${OPENSSL:=openssl}"
: "${PLUTIL:=plutil}"

usage() {
    print -u2 -r -- "usage: $0 --source-plist FILE --app APP --dmg DMG --appcast FILE --provenance FILE [--previous-appcast FILE]"
    exit 2
}

source_plist=""
app=""
dmg=""
appcast=""
provenance=""
previous_appcast=""
while (( $# > 0 )); do
    case "$1" in
        --source-plist)
            [[ -z "$source_plist" && $# -ge 2 ]] || usage
            source_plist="$2"
            shift 2
            ;;
        --app)
            [[ -z "$app" && $# -ge 2 ]] || usage
            app="$2"
            shift 2
            ;;
        --dmg)
            [[ -z "$dmg" && $# -ge 2 ]] || usage
            dmg="$2"
            shift 2
            ;;
        --appcast)
            [[ -z "$appcast" && $# -ge 2 ]] || usage
            appcast="$2"
            shift 2
            ;;
        --provenance)
            [[ -z "$provenance" && $# -ge 2 ]] || usage
            provenance="$2"
            shift 2
            ;;
        --previous-appcast)
            [[ -z "$previous_appcast" && $# -ge 2 ]] || usage
            previous_appcast="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done
[[ -n "$source_plist$app$dmg$appcast$provenance" ]] || usage

cd "$repo_root"
source "$script_dir/release-sparkle-lib.sh"
source "$script_dir/release-version-lib.sh"
release_load_identity "$repo_root"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"

source_plist="${source_plist:A}"
app="${app:A}"
dmg="${dmg:A}"
appcast="${appcast:A}"
provenance="${provenance:A}"
if [[ -n "$previous_appcast" ]]; then
    previous_appcast="${previous_appcast:A}"
fi

[[ -f "$source_plist" ]] || release_fail "source Info.plist does not exist: $source_plist"
[[ -d "$app" ]] || release_fail "release app does not exist: $app"
[[ -f "$dmg" ]] || release_fail "release DMG does not exist: $dmg"
[[ -f "$appcast" ]] || release_fail "release appcast does not exist: $appcast"
[[ -f "$provenance" ]] || release_fail "release provenance does not exist: $provenance"
[[ -z "$previous_appcast" || -f "$previous_appcast" ]] || release_fail "previous appcast does not exist: $previous_appcast"

plist_value() {
    "$PLUTIL" -extract "$2" raw "$1"
}

verify_version_and_build() {
    local plist="$1"
    local label="$2"
    [[ "$(plist_value "$plist" CFBundleShortVersionString)" == "$RELEASE_VERSION" ]] || \
        release_fail "$label version mismatch: expected $RELEASE_VERSION"
    [[ "$(plist_value "$plist" CFBundleVersion)" == "$RELEASE_BUILD" ]] || \
        release_fail "$label build mismatch: expected $RELEASE_BUILD"
}

verify_public_key() {
    local plist="$1"
    local label="$2"
    local key
    key="$(plist_value "$plist" SUPublicEDKey)" || release_fail "$label is missing SUPublicEDKey"
    release_validate_sparkle_public_key "$key" || release_fail "$label SUPublicEDKey must decode to 32 bytes"
    print -r -- "$key"
}

verify_app_metadata() {
    local candidate_app="$1"
    local label="$2"
    local expected_key="$3"
    local plist="$candidate_app/Contents/Info.plist"
    local executable="$candidate_app/Contents/MacOS/Drift"

    [[ -f "$plist" ]] || release_fail "$label Info.plist does not exist"
    [[ -x "$executable" ]] || release_fail "$label executable does not exist"
    verify_version_and_build "$plist" "$label"
    [[ "$(plist_value "$plist" CFBundleIdentifier)" == "com.woosublee.drift" ]] || \
        release_fail "$label bundle identifier mismatch: expected com.woosublee.drift"
    [[ "$(plist_value "$plist" SUFeedURL)" == "$RELEASE_FEED_URL" ]] || \
        release_fail "$label SUFeedURL mismatch: expected $RELEASE_FEED_URL"
    [[ "$(verify_public_key "$plist" "$label")" == "$expected_key" ]] || \
        release_fail "$label SUPublicEDKey mismatch"

    local architectures
    architectures="$("$LIPO" -archs "$executable" | tr ' ' '\n' | sort | paste -sd ' ' -)"
    [[ "$architectures" == "arm64 x86_64" ]] || \
        release_fail "$label architectures mismatch: expected arm64 x86_64; found ${architectures:-none}"
}

extract_certificate_metadata() {
    local candidate_app="$1"
    local certificate_directory
    certificate_directory="$(mktemp -d "${TMPDIR:-/tmp}/drift-release-verification-cert.XXXXXX")"
    local certificate_prefix="$certificate_directory/certificate-"
    local certificate="$certificate_prefix"0
    "$CODESIGN" -d "--extract-certificates=$certificate_prefix" "$candidate_app" >/dev/null 2>&1 || {
        rm -rf "$certificate_directory"
        release_fail "could not extract signing certificate from release app"
        return
    }
    [[ -f "$certificate" ]] || {
        rm -rf "$certificate_directory"
        release_fail "codesign did not extract a signing certificate"
        return
    }
    local certificate_common_name certificate_sha256
    certificate_common_name="$("$OPENSSL" x509 -inform DER -in "$certificate" -noout -subject -nameopt RFC2253 | python3 -c '
import re
import sys
match = re.fullmatch(r"subject=CN=([^,]+)", sys.stdin.read().strip())
if not match:
    raise SystemExit("ERROR: signing certificate subject must contain only CN")
print(match.group(1))
')" || {
        rm -rf "$certificate_directory"
        return 1
    }
    certificate_sha256="$("$OPENSSL" x509 -inform DER -in "$certificate" -noout -fingerprint -sha256 | python3 -c '
import re
import sys
match = re.fullmatch(r"sha256 Fingerprint=([0-9A-Fa-f:]+)", sys.stdin.read().strip())
if not match:
    raise SystemExit("ERROR: could not parse signing certificate SHA-256 fingerprint")
value = match.group(1).replace(":", "").upper()
if not re.fullmatch(r"[0-9A-F]{64}", value):
    raise SystemExit("ERROR: signing certificate SHA-256 fingerprint must contain 64 hex characters")
print(value)
')" || {
        rm -rf "$certificate_directory"
        return 1
    }
    rm -rf "$certificate_directory"
    print -r -- "$certificate_common_name $certificate_sha256"
}

source_key="$(verify_public_key "$source_plist" "source Info.plist")"
verify_version_and_build "$source_plist" "source Info.plist"
[[ "$(plist_value "$source_plist" CFBundleIdentifier)" == "com.woosublee.drift" ]] || \
    release_fail "source Info.plist bundle identifier mismatch: expected com.woosublee.drift"

verify_app_metadata "$app" "release app" "$source_key"
"$CODESIGN" --verify --deep --strict --verbose=2 "$app"
"$CODESIGN" --verify --strict --verbose=2 "$dmg"

mountpoint="$(mktemp -d "${TMPDIR:-/tmp}/drift-release-verification-mount.XXXXXX")"
mounted=0
cleanup() {
    if (( mounted )); then
        "$HDIUTIL" detach "$mountpoint" >/dev/null 2>&1 || \
            "$HDIUTIL" detach -force "$mountpoint" >/dev/null 2>&1 || true
    fi
    rm -rf "$mountpoint"
}
trap cleanup EXIT
"$HDIUTIL" attach -readonly -nobrowse -mountpoint "$mountpoint" "$dmg" >/dev/null
mounted=1
mounted_app="$mountpoint/Drift.app"
if ! verify_app_metadata "$mounted_app" "mounted DMG app" "$source_key"; then
    exit 1
fi
if ! "$CODESIGN" --verify --deep --strict --verbose=2 "$mounted_app"; then
    exit 1
fi
if ! "$CODESIGN" --verify --strict --verbose=2 "$dmg"; then
    exit 1
fi
if ! "$HDIUTIL" detach "$mountpoint"; then
    release_fail "could not detach release DMG"
fi
mounted=0

read -r appcast_build appcast_short_version enclosure_url enclosure_length enclosure_type enclosure_signature enclosure_build enclosure_short_version <<EOF
$(python3 - "$appcast" <<'PY'
import sys
import xml.etree.ElementTree as ET

namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError) as error:
    raise SystemExit(f'ERROR: could not parse appcast: {error}')
item = next(iter(root.iter('item')), None)
if item is None:
    raise SystemExit('ERROR: appcast is missing an item')
enclosure = item.find('enclosure')
if enclosure is None:
    raise SystemExit('ERROR: appcast item is missing an enclosure')
def value(name):
    current = enclosure.get(name)
    if not isinstance(current, str) or not current:
        raise SystemExit(f'ERROR: appcast enclosure is missing {name}')
    return current
item_build = item.findtext(f'{namespace}version')
item_short_version = item.findtext(f'{namespace}shortVersionString')
if not isinstance(item_build, str) or not item_build:
    raise SystemExit('ERROR: appcast item is missing sparkle:version')
if not isinstance(item_short_version, str) or not item_short_version:
    raise SystemExit('ERROR: appcast item is missing sparkle:shortVersionString')
print('\t'.join((
    item_build,
    item_short_version,
    value('url'),
    value('length'),
    value('type'),
    value(f'{namespace}edSignature'),
    value(f'{namespace}version'),
    value(f'{namespace}shortVersionString'),
)))
PY
)
EOF
[[ "$appcast_build" == "$RELEASE_BUILD" && "$enclosure_build" == "$RELEASE_BUILD" ]] || \
    release_fail "appcast build mismatch: expected $RELEASE_BUILD"
[[ "$appcast_short_version" == "$RELEASE_VERSION" && "$enclosure_short_version" == "$RELEASE_VERSION" ]] || \
    release_fail "appcast version mismatch: expected $RELEASE_VERSION"
[[ "$enclosure_url" == "$RELEASE_DOWNLOAD_URL" ]] || \
    release_fail "appcast enclosure URL mismatch: expected $RELEASE_DOWNLOAD_URL"
[[ "${enclosure_url:t}" == "$RELEASE_DMG_NAME" ]] || \
    release_fail "appcast enclosure filename mismatch: expected $RELEASE_DMG_NAME"
[[ "$enclosure_type" == "application/octet-stream" ]] || \
    release_fail "appcast enclosure type mismatch: expected application/octet-stream"
[[ -n "$enclosure_signature" ]] || release_fail "appcast enclosure signature is empty"
actual_dmg_length="$(wc -c < "$dmg" | tr -d ' ')"
[[ "$enclosure_length" == "$actual_dmg_length" ]] || release_fail "appcast enclosure length mismatch: expected $actual_dmg_length"

private_key="$(release_sparkle_private_key)" || release_fail "could not read Sparkle private key"
[[ -n "$private_key" ]] || release_fail "Sparkle private key is empty"
sign_update="$SIGN_UPDATE"
if [[ -z "$sign_update" ]]; then
    sign_update="$(release_find_sign_update)" || release_fail "could not find Sparkle sign_update"
fi
[[ -x "$sign_update" ]] || release_fail "Sparkle sign_update is not executable"
if ! print -rn -- "$private_key" | "$sign_update" --verify --ed-key-file - "$dmg" "$enclosure_signature" >/dev/null 2>&1; then
    release_fail "Sparkle signature verification failed"
fi

if [[ -n "$previous_appcast" ]]; then
    previous_build="$(release_appcast_extract_enclosure_version "$previous_appcast")" || exit 1
    release_positive_integer_greater_than "$RELEASE_BUILD" "$previous_build" || \
        release_fail "current build $RELEASE_BUILD must be greater than previous build $previous_build"
fi

certificate_metadata="$(extract_certificate_metadata "$app")"
certificate_common_name="${certificate_metadata%% *}"
certificate_sha256="${certificate_metadata#* }"
commit="$($GIT rev-parse HEAD)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || release_fail "Git HEAD must be a 40-character lowercase commit SHA"
previous_metadata="${provenance:h}/previous-release.json"
[[ -f "$previous_metadata" ]] || release_fail "previous release metadata does not exist: $previous_metadata"

python3 - \
    "$provenance" \
    "$previous_metadata" \
    "$RELEASE_VERSION" \
    "$RELEASE_BUILD" \
    "$RELEASE_TAG" \
    "$commit" \
    "$RELEASE_FEED_URL" \
    "$RELEASE_DOWNLOAD_URL" \
    "$source_key" \
    "$certificate_common_name" \
    "$certificate_sha256" \
    "$dmg" \
    "$appcast" <<'PY'
import hashlib
import json
import os
import re
import sys

(
    provenance_path,
    previous_path,
    version,
    build,
    tag,
    commit,
    feed_url,
    download_url,
    public_key,
    certificate_common_name,
    certificate_sha256,
    dmg_path,
    appcast_path,
) = sys.argv[1:]

with open(provenance_path, encoding='utf-8') as handle:
    provenance = json.load(handle)
if type(provenance) is not dict:
    raise SystemExit('ERROR: provenance must be a JSON object')
expected_top_level_keys = {'schemaVersion', 'release', 'signing', 'artifacts', 'build', 'previous'}
if set(provenance) != expected_top_level_keys:
    raise SystemExit('ERROR: provenance has unknown or missing top-level keys')
if provenance['schemaVersion'] != 1:
    raise SystemExit('ERROR: provenance schema version mismatch')

def require_mapping(name, expected_keys):
    value = provenance[name]
    if type(value) is not dict or set(value) != expected_keys:
        raise SystemExit(f'ERROR: provenance {name} has an invalid shape')
    return value

release = require_mapping(
    'release',
    {'version', 'build', 'tag', 'commit', 'repository', 'bundleIdentifier', 'architectures', 'feedURL', 'downloadURL'},
)
signing = require_mapping('signing', {'certificateCommonName', 'certificateSHA256', 'sparklePublicKey'})
artifacts = require_mapping('artifacts', {'dmg', 'appcast'})
require_mapping('build', {'timestamp', 'workflowRunID'})

expected_release = {
    'version': version,
    'build': int(build),
    'tag': tag,
    'commit': commit,
    'repository': 'woosublee/drift',
    'bundleIdentifier': 'com.woosublee.drift',
    'architectures': ['arm64', 'x86_64'],
    'feedURL': feed_url,
    'downloadURL': download_url,
}
if release != expected_release:
    raise SystemExit('ERROR: provenance release identity mismatch')
if signing['certificateCommonName'] != certificate_common_name:
    raise SystemExit('ERROR: provenance certificate common name mismatch')
if signing['certificateSHA256'] != certificate_sha256:
    raise SystemExit('ERROR: provenance certificate SHA-256 mismatch')
if signing['sparklePublicKey'] != public_key:
    raise SystemExit('ERROR: provenance Sparkle public key mismatch')

def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

def verify_artifact(name, path):
    expected = {'name': os.path.basename(path), 'bytes': os.path.getsize(path), 'sha256': digest(path)}
    if type(artifacts[name]) is not dict or set(artifacts[name]) != set(expected):
        raise SystemExit(f'ERROR: provenance {name} artifact has an invalid shape')
    for key, value in expected.items():
        if artifacts[name][key] != value:
            label = 'DMG' if name == 'dmg' else 'appcast'
            rendered_key = 'SHA-256' if key == 'sha256' else key
            raise SystemExit(f'ERROR: provenance {label} {rendered_key} mismatch')

verify_artifact('dmg', dmg_path)
verify_artifact('appcast', appcast_path)

with open(previous_path, encoding='utf-8') as handle:
    previous_metadata = json.load(handle)
if type(previous_metadata) is not dict or set(previous_metadata) != {'source', 'previous'}:
    raise SystemExit('ERROR: previous release metadata has an invalid shape')
previous = previous_metadata['previous']
if previous is not None:
    if type(previous) is not dict or set(previous) != {'version', 'build', 'tag', 'dmgName'}:
        raise SystemExit('ERROR: previous release metadata has an invalid previous value')
    if (
        type(previous['version']) is not str
        or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', previous['version'])
        or type(previous['build']) is not int
        or isinstance(previous['build'], bool)
        or previous['build'] <= 0
        or previous['tag'] != f"v{previous['version']}"
        or previous['dmgName'] != f"Drift-{previous['version']}.dmg"
    ):
        raise SystemExit('ERROR: previous release metadata has an invalid previous value')
if provenance['previous'] != previous:
    raise SystemExit('ERROR: provenance previous release mismatch')
PY
