#!/bin/zsh

release_sparkle_private_key() {
    if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        print -r -- "$SPARKLE_PRIVATE_KEY"
    else
        security find-generic-password \
            -s "${SPARKLE_KEYCHAIN_SERVICE:-https://sparkle-project.org}" \
            -a "${SPARKLE_ACCOUNT:-com.woosublee.drift.sparkle.ed25519}" \
            -w 2>/dev/null
    fi
}

release_find_sign_update() {
    if [[ -n "${SPARKLE_SIGN_UPDATE:-}" ]] && [[ -x "$SPARKLE_SIGN_UPDATE" ]]; then
        print -r -- "$SPARKLE_SIGN_UPDATE"
        return
    fi

    local candidate
    for candidate in .build/artifacts/**/sign_update(N.); do
        [[ -x "$candidate" ]] || continue
        print -r -- "$candidate"
        return
    done

    print -u2 -r -- "ERROR: could not find Sparkle sign_update"
    return 1
}

release_verify_signature() {
    local dmg="$1"
    local signature="$2"
    local sign_update
    sign_update="$(release_find_sign_update)" || return

    release_sparkle_private_key | "$sign_update" --verify --ed-key-file - "$dmg" "$signature"
}
