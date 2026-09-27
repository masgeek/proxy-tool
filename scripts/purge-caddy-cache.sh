#!/usr/bin/env bash
set -Eeuo pipefail

admin_url=${CADDY_ADMIN_URL:-http://127.0.0.1:2019}
api_url=${CADDY_CACHE_API_URL:-"$admin_url/souin-api/souin"}

if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' 'curl is not installed or not in PATH.' >&2
    exit 1
fi

curl --fail --silent --show-error --request PURGE \
    --header "Origin: $admin_url" \
    "$api_url/flush"
printf 'Cache purge requested: %s/flush\n' "$api_url"
