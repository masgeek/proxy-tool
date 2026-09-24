#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' 'Run this script as root.' >&2
    exit 1
fi

if ! command -v caddy >/dev/null 2>&1; then
    printf '%s\n' 'caddy is not installed or not in PATH.' >&2
    exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_dir=${1:-"$script_dir/../config/caddy"}
target_dir=${CADDY_TARGET_DIR:-/etc/caddy}

if [ ! -f "$source_dir/Caddyfile" ]; then
    printf 'Source Caddyfile not found: %s\n' "$source_dir/Caddyfile" >&2
    exit 1
fi

stage_dir=$(mktemp -d)
trap 'rm -rf "$stage_dir"' EXIT
cp -a "$source_dir"/. "$stage_dir"/

caddy validate --config "$stage_dir/Caddyfile"

install -d -m 0755 "$target_dir"
backup_dir="$target_dir/backups"
install -d -m 0755 "$backup_dir"
timestamp=$(date +%Y%m%d%H%M%S)
backup_path="$backup_dir/caddy-$timestamp.tar.gz"
backup_paths=()

if [ -f "$target_dir/Caddyfile" ]; then
    backup_paths+=(Caddyfile)
fi
if [ -d "$target_dir/snippets" ]; then
    backup_paths+=(snippets)
fi
if [ "${#backup_paths[@]}" -gt 0 ]; then
    tar -czf "$backup_path" -C "$target_dir" "${backup_paths[@]}"
    printf 'Backup created: %s\n' "$backup_path"
else
    printf '%s\n' 'No existing Caddyfile found; skipping backup.'
fi

cp -a "$stage_dir"/. "$target_dir"/

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy; then
    systemctl reload caddy
else
    caddy reload --config "$target_dir/Caddyfile"
fi

printf 'Caddy deployed successfully from %s\n' "$source_dir"
