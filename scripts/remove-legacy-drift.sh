#!/bin/zsh
set -euo pipefail

legacy_bundle_id="com.woosublee.Drift"
installed_app="${LEGACY_INSTALLED_APP:-$HOME/Applications/Drift.app}"
temporary_root="${LEGACY_TEMP_ROOT:-/tmp/drift-bundles}"
tccutil_bin="${TCCUTIL_BIN:-/usr/bin/tccutil}"
lsregister_bin="${LSREGISTER_BIN:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
# Test-only override for isolated discovery-failure coverage; production defaults to /usr/bin/find.
find_bin="${FIND_BIN:-/usr/bin/find}"

candidate_snapshot=""
cleanup_candidate_snapshot() {
    [[ -n "$candidate_snapshot" && -e "$candidate_snapshot" ]] && rm -f "$candidate_snapshot"
}
trap cleanup_candidate_snapshot EXIT

[[ -x "$find_bin" ]] || {
    print -u2 -- "BLOCKED: discovery tool is not executable: $find_bin"
    exit 1
}
if ! candidate_snapshot="$(mktemp "${TMPDIR:-/tmp}/drift-legacy-candidates.XXXXXX")"; then
    print -u2 -- "BLOCKED: could not create discovery snapshot"
    exit 1
fi

if [[ -d "$temporary_root" ]] && ! "$find_bin" "$temporary_root" -type d -name 'Drift.app' -print0 > "$candidate_snapshot"; then
    print -u2 -- "BLOCKED: discovery failed: $temporary_root"
    exit 1
fi

typeset -a candidates
[[ -d "$installed_app" ]] && candidates+=("$installed_app")
while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
done < "$candidate_snapshot"

if (( ${#candidates[@]} == 0 )); then
    print -r -- "No legacy Drift bundles found"
    exit 0
fi

for candidate in "${candidates[@]}"; do
    plist="$candidate/Contents/Info.plist"
    [[ -f "$plist" && -r "$plist" ]] || {
        print -u2 -- "BLOCKED: Missing or unreadable Info.plist: $candidate"
        exit 1
    }
    if ! bundle_id="$(plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null)"; then
        print -u2 -- "BLOCKED: Unreadable Bundle ID: $candidate"
        exit 1
    fi
    [[ "$bundle_id" == "$legacy_bundle_id" ]] || {
        print -u2 -- "BLOCKED: Refusing non-legacy bundle: $candidate ($bundle_id)"
        exit 1
    }
done

[[ -x "$lsregister_bin" ]] || {
    print -u2 -- "BLOCKED: LaunchServices tool is not executable: $lsregister_bin"
    exit 1
}
[[ -x "$tccutil_bin" ]] || {
    print -u2 -- "BLOCKED: tccutil tool is not executable: $tccutil_bin"
    exit 1
}

"$lsregister_bin" -f "${candidates[1]}"
"$tccutil_bin" reset Accessibility "$legacy_bundle_id"

for candidate in "${candidates[@]}"; do
    "$lsregister_bin" -u "$candidate"
    rm -rf "$candidate"
    print -r -- "Removed legacy bundle: $candidate"
done
