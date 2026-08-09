#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    echo "usage: $0 <path-to-app>" >&2
    exit 2
fi

app="$1"

if [[ ! -d "$app" ]]; then
    echo "app bundle does not exist: $app" >&2
    exit 2
fi

if xattr -lr "$app" 2>/dev/null | LC_ALL=C grep -aE '(^|[[:space:]])(com\.apple\.FinderInfo|com\.apple\.fileprovider\.fpfs#P):' >/dev/null; then
    echo "Forbidden signing metadata remains in $app" >&2
    exit 1
fi
