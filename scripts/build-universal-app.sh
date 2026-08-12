#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
: "${SWIFT:=swift}"
: "${LIPO:=lipo}"
: "${MAKE:=make}"

cd "$repo_root"
eval "$("$script_dir/resolve-release-version.sh" shell)"

release_root="$repo_root/build/release"
arm_scratch="$release_root/swift-arm64"
x86_scratch="$release_root/swift-x86_64"
universal_executable="$release_root/universal/Drift"

"$SWIFT" build -c release --product Drift \
    --scratch-path "$arm_scratch" --triple arm64-apple-macosx13.0
"$SWIFT" build -c release --product Drift \
    --scratch-path "$x86_scratch" --triple x86_64-apple-macosx13.0
arm_bin="$("$SWIFT" build -c release --show-bin-path \
    --scratch-path "$arm_scratch" --triple arm64-apple-macosx13.0)"
x86_bin="$("$SWIFT" build -c release --show-bin-path \
    --scratch-path "$x86_scratch" --triple x86_64-apple-macosx13.0)"

mkdir -p "${universal_executable:h}"
"$LIPO" -create "$arm_bin/Drift" "$x86_bin/Drift" -output "$universal_executable"

sparkle_framework="$(find "$arm_scratch" -type d -name Sparkle.framework -print -quit)"
if [[ -z "$sparkle_framework" ]]; then
    print -u2 -r -- "Sparkle.framework was not produced by the arm64 SwiftPM build"
    exit 1
fi

"$MAKE" -C "$repo_root" bundle-prebuilt \
    CONFIGURATION=release APP_VARIANT=production BUILD_DIR="$release_root" \
    CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Drift}" \
    PREBUILT_EXECUTABLE="$universal_executable" \
    PREBUILT_SPARKLE_FRAMEWORK="$sparkle_framework" \
    SPARKLE_FEED_URL="$RELEASE_FEED_URL" \
    SPARKLE_PUBLIC_ED_KEY="$(plutil -extract SUPublicEDKey raw "$repo_root/Info.plist")"

architectures="$("$LIPO" -archs "$release_root/Drift.app/Contents/MacOS/Drift" | tr ' ' '\n' | sort | paste -sd ' ' -)"
if [[ "$architectures" != "arm64 x86_64" ]]; then
    print -u2 -r -- "Release executable architectures must be exactly arm64 x86_64; found: $architectures"
    exit 1
fi

"$script_dir/verify-app-bundle.sh" "$release_root/Drift.app" \
    production-configured com.woosublee.drift Drift
