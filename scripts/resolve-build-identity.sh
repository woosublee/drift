#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
    echo "usage: $0 <debug|release> <production|dev|empty> <field>" >&2
    exit 2
fi

configuration="$1"
requested_variant="$2"
field="$3"

case "$configuration" in
    debug|release) ;;
    *)
        echo "CONFIGURATION must be debug or release" >&2
        exit 2
        ;;
esac

if [[ -n "$requested_variant" ]]; then
    variant="$requested_variant"
else
    case "$configuration" in
        debug) variant="dev" ;;
        release) variant="production" ;;
        *)
            echo "CONFIGURATION must be debug or release" >&2
            exit 2
            ;;
    esac
fi

case "$variant" in
    production)
        product_name="Drift"
        bundle_id="com.woosublee.drift"
        accessibility_description="Drift needs Accessibility access to move the pointer."
        ;;
    dev)
        product_name="Drift Dev"
        bundle_id="com.woosublee.drift.dev"
        accessibility_description="Drift Dev needs Accessibility access to move the pointer."
        ;;
    *)
        echo "APP_VARIANT must be production or dev" >&2
        exit 2
        ;;
esac

case "$field" in
    variant) print -r -- "$variant" ;;
    product-name) print -r -- "$product_name" ;;
    bundle-id) print -r -- "$bundle_id" ;;
    accessibility-description) print -r -- "$accessibility_description" ;;
    *)
        echo "field must be variant, product-name, bundle-id, or accessibility-description" >&2
        exit 2
        ;;
esac
