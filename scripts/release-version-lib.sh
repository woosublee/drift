#!/bin/zsh

release_fail() {
    print -u2 -r -- "ERROR: $1"
    return 1
}

release_is_stable_semver() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

release_is_positive_int64() {
    local value="$1"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
    (( ${#value} < 19 )) && return 0
    (( ${#value} > 19 )) && return 1
    [[ "$value" < 9223372036854775807 || "$value" == 9223372036854775807 ]]
}

release_is_nonnegative_int64() {
    local value="$1"
    [[ "$value" == "0" ]] && return 0
    release_is_positive_int64 "$value"
}

release_positive_integer_greater_than() {
    local value="$1"
    local minimum="$2"
    release_is_positive_int64 "$value" && release_is_positive_int64 "$minimum" && (( value > minimum ))
}

release_validate_sparkle_public_key() {
    local key="$1"
    python3 - "$key" <<'PY'
import base64
import sys

value = sys.argv[1]
try:
    decoded = base64.b64decode(value, validate=True)
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if len(value) == 44 and value.endswith('=') and value.count('=') == 1 and len(decoded) == 32 else 1)
PY
}

release_atomic_replace() {
    local source="$1"
    local destination="$2"
    [[ -f "$source" ]] || release_fail "replacement source does not exist: $source"
    mv -f "$source" "$destination"
}

release_appcast_extract_enclosure_attribute() {
    local appcast="$1"
    local attribute="$2"
    python3 - "$appcast" "$attribute" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, attribute = sys.argv[1:]
try:
    root = ET.parse(appcast).getroot()
except (ET.ParseError, OSError) as error:
    raise SystemExit(f"ERROR: could not parse appcast: {error}")
for enclosure in root.iter("enclosure"):
    value = enclosure.get(attribute)
    if value is not None:
        print(value)
        break
else:
    raise SystemExit(f"ERROR: appcast enclosure is missing {attribute}")
PY
}

release_appcast_extract_enclosure_url() {
    release_appcast_extract_enclosure_attribute "$1" url
}

release_appcast_extract_enclosure_version() {
    release_appcast_extract_enclosure_attribute "$1" '{http://www.andymatuschak.org/xml-namespaces/sparkle}version'
}

release_appcast_extract_item_short_version() {
    local appcast="$1"
    python3 - "$appcast" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError) as error:
    raise SystemExit(f"ERROR: could not parse appcast: {error}")
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
for item in root.iter('item'):
    value = item.findtext(f'{namespace}shortVersionString')
    if value is not None:
        print(value)
        break
else:
    raise SystemExit('ERROR: appcast item is missing sparkle:shortVersionString')
PY
}

release_load_identity() {
    local repo_root="$1"
    local metadata="$repo_root/release/version.json"

    [[ -f "$metadata" ]] || release_fail "release/version.json does not exist"
    python3 - "$metadata" <<'PY' >/dev/null
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
if type(value) is not dict or set(value) != {"marketingVersion", "buildNumber"}:
    raise SystemExit("ERROR: release/version.json must contain exactly marketingVersion and buildNumber")
if type(value["marketingVersion"]) is not str:
    raise SystemExit("ERROR: marketingVersion must be a JSON string")
if type(value["buildNumber"]) is not int or isinstance(value["buildNumber"], bool):
    raise SystemExit("ERROR: buildNumber must be a JSON integer")
PY
    RELEASE_VERSION="$(plutil -extract marketingVersion raw "$metadata")"
    RELEASE_BUILD="$(plutil -extract buildNumber raw "$metadata")"
    release_is_stable_semver "$RELEASE_VERSION" || release_fail 'marketingVersion must use stable SemVer x.y.z'
    release_is_positive_int64 "$RELEASE_BUILD" || release_fail 'buildNumber must be a positive 64-bit integer'
    RELEASE_TAG="v$RELEASE_VERSION"
    RELEASE_DMG_NAME="Drift-$RELEASE_VERSION.dmg"
    RELEASE_DMG_PATH="build/release/$RELEASE_DMG_NAME"
    RELEASE_APPCAST_PATH="build/release/appcast.xml"
    RELEASE_PROVENANCE_PATH="build/release/release-provenance.json"
    RELEASE_FEED_URL="https://github.com/woosublee/drift/releases/latest/download/appcast.xml"
    RELEASE_DOWNLOAD_URL="https://github.com/woosublee/drift/releases/download/$RELEASE_TAG/$RELEASE_DMG_NAME"
}
