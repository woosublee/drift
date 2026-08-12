#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"

cd "$repo_root"
source "$script_dir/release-sparkle-lib.sh"
eval "$("$script_dir/resolve-release-version.sh" shell)"

canonical_dmg="$repo_root/$RELEASE_DMG_PATH"
[[ -f "$canonical_dmg" ]] || {
    print -u2 -r -- "ERROR: canonical release DMG does not exist: $RELEASE_DMG_PATH"
    exit 1
}

expected_public_key="$(plutil -extract SUPublicEDKey raw "$repo_root/Info.plist")" || {
    print -u2 -r -- "ERROR: Info.plist is missing SUPublicEDKey"
    exit 1
}

private_key="$(release_sparkle_private_key)" || {
    print -u2 -r -- "ERROR: could not read Sparkle private key"
    exit 1
}
[[ -n "$private_key" ]] || {
    print -u2 -r -- "ERROR: Sparkle private key is empty"
    exit 1
}

print -rn -- "$private_key" | xcrun swift "$script_dir/validate-sparkle-key.swift" "$expected_public_key"

sign_update="$(release_find_sign_update)"
[[ -x "$sign_update" ]] || {
    print -u2 -r -- "ERROR: Sparkle sign_update is not executable"
    exit 1
}

signature_output="$(print -rn -- "$private_key" | "$sign_update" "$canonical_dmg" --ed-key-file -)"
ed_signature="$(print -r -- "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$ed_signature" ]] || {
    print -u2 -r -- "ERROR: sign_update did not produce exactly one sparkle:edSignature"
    exit 1
}
[[ "$(print -r -- "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | wc -l | tr -d ' ')" == "1" ]] || {
    print -u2 -r -- "ERROR: sign_update did not produce exactly one sparkle:edSignature"
    exit 1
}

release_verify_signature "$canonical_dmg" "$ed_signature"

length="$(wc -c < "$canonical_dmg" | tr -d ' ')"
pub_date="$(LC_ALL=C TZ=UTC date '+%a, %d %b %Y %H:%M:%S +0000')"
release_notes_url="https://github.com/woosublee/drift/releases/tag/$RELEASE_TAG"
appcast="$repo_root/$RELEASE_APPCAST_PATH"
mkdir -p "${appcast:h}"
temporary_appcast="$(mktemp "${appcast:h}/.${appcast:t}.XXXXXX")"
trap 'rm -f "$temporary_appcast"' EXIT

cat > "$temporary_appcast" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Drift Updates</title>
    <link>$RELEASE_FEED_URL</link>
    <description>Updates for Drift</description>
    <item>
      <title>Drift $RELEASE_VERSION</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$RELEASE_BUILD</sparkle:version>
      <sparkle:shortVersionString>$RELEASE_VERSION</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>$release_notes_url</sparkle:releaseNotesLink>
      <enclosure url="$RELEASE_DOWNLOAD_URL" length="$length" type="application/octet-stream" sparkle:edSignature="$ed_signature" sparkle:version="$RELEASE_BUILD" sparkle:shortVersionString="$RELEASE_VERSION" />
    </item>
  </channel>
</rss>
EOF

xmllint --noout "$temporary_appcast"
mv -f "$temporary_appcast" "$appcast"
trap - EXIT
