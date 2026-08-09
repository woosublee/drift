#!/bin/zsh
set -euo pipefail

if (( $# != 4 )); then
    echo "usage: $0 <app> <development|production-unconfigured|production-configured> <bundle-id> <product-name>" >&2
    exit 2
fi

app="$1"
mode="$2"
bundle_id="$3"
product_name="$4"
plist="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/Drift"
framework="$app/Contents/Frameworks/Sparkle.framework"

[[ -d "$app" ]]
[[ -f "$plist" ]]
[[ -x "$executable" ]]
[[ -d "$framework" ]]

test "${app:t}" = "$product_name.app"
test "$(plutil -extract CFBundleIdentifier raw "$plist")" = "$bundle_id"
test "$(plutil -extract CFBundleName raw "$plist")" = "$product_name"
test "$(plutil -extract CFBundleDisplayName raw "$plist")" = "$product_name"
test "$(plutil -extract CFBundleExecutable raw "$plist")" = "Drift"
test "$(plutil -extract NSAccessibilityAccessDescription raw "$plist")" = \
    "$product_name needs Accessibility access to move the pointer."

designated_requirement="$(codesign -d -r- "$app" 2>&1)"
grep -F "identifier \"$bundle_id\"" <<<"$designated_requirement" >/dev/null
! grep -Fq 'cdhash' <<<"$designated_requirement"

codesign --verify --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$framework"
test "$(plutil -extract LSMinimumSystemVersion raw "$plist")" = "13.0"
test "$(plutil -extract LSUIElement raw "$plist")" = "true"
otool -l "$executable" | grep -A2 LC_RPATH | grep -F '@executable_path/../Frameworks' >/dev/null

for privacy_key in \
    NSAppleEventsUsageDescription \
    NSCameraUsageDescription \
    NSMicrophoneUsageDescription \
    NSScreenCaptureUsageDescription; do
    ! plutil -extract "$privacy_key" raw "$plist" >/dev/null 2>&1
done

[[ ! -e "$app/Contents/PlugIns" ]]
! find "$app/Contents" -path '*/LoginItems/*.app' -print -quit | grep -q .
! otool -L "$executable" | grep -Fq StoreKit
! grep -aiE -q 'gumroad\.com|upgrade[_ -]?to[_ -]?pro|restore[_ -]?purchases' "$executable"

verify_public_key() {
    local key
    key="$(plutil -extract SUPublicEDKey raw "$plist")"
    if ! python3 -c 'import base64,sys; value=sys.argv[1]; sys.exit(0 if len(value) == 44 and value.endswith("=") and value.count("=") == 1 and len(base64.b64decode(value, validate=True)) == 32 else 1)' "$key" 2>/dev/null; then
        echo "Sparkle public key must be a 44-character padded Base64 value decoding to 32 bytes" >&2
        return 1
    fi
}

case "$mode" in
    development)
        ! plutil -extract SUFeedURL raw "$plist" >/dev/null 2>&1
        ! plutil -extract SUPublicEDKey raw "$plist" >/dev/null 2>&1
        ;;
    production-unconfigured)
        ! plutil -extract SUFeedURL raw "$plist" >/dev/null 2>&1
        verify_public_key
        ;;
    production-configured)
        test "$(plutil -extract SUFeedURL raw "$plist" | cut -c1-8)" = "https://"
        verify_public_key
        ;;
    *)
        echo "invalid update mode: $mode" >&2
        exit 2
        ;;
esac
