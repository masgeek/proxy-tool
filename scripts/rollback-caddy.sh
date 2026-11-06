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

target_dir=${CADDY_TARGET_DIR:-/etc/caddy}
backup_dir="$target_dir/backups"

if [ ! -d "$backup_dir" ]; then
    printf 'Backup directory not found: %s\n' "$backup_dir" >&2
    exit 1
fi

backup_path=${1:-}
if [ -z "$backup_path" ]; then
    for candidate in "$backup_dir"/caddy-*.tar.gz; do
        if [ -f "$candidate" ]; then
            backup_path=$candidate
        fi
    done
fi

if [ -z "$backup_path" ] || [ ! -f "$backup_path" ]; then
    printf '%s\n' 'No Caddy backup was found.' >&2
    exit 1
fi

restore_dir=$(mktemp -d)
trap 'rm -rf "$restore_dir"' EXIT
tar -xzf "$backup_path" -C "$restore_dir"

if [ ! -f "$restore_dir/Caddyfile" ]; then
    printf 'Backup does not contain Caddyfile: %s\n' "$backup_path" >&2
    exit 1
fi

if [ -f "$target_dir/Caddyfile" ] || [ -d "$target_dir/snippets" ]; then
    current_backup="$backup_dir/caddy-pre-rollback-$(date +%Y%m%d%H%M%S).tar.gz"
    current_paths=()
    [ -f "$target_dir/Caddyfile" ] && current_paths+=(Caddyfile)
    [ -d "$target_dir/snippets" ] && current_paths+=(snippets)
    if [ "${#current_paths[@]}" -gt 0 ]; then
        tar -czf "$current_backup" -C "$target_dir" "${current_paths[@]}"
        printf 'Current configuration backed up: %s\n' "$current_backup"
    fi
fi

install -d -m 0755 "$target_dir"
rm -f "$target_dir/Caddyfile"
if [ -d "$restore_dir/snippets" ]; then
    rm -rf "$target_dir/snippets"
    cp -a "$restore_dir/snippets" "$target_dir/snippets"
else
    rm -rf "$target_dir/snippets"
fi
cp -a "$restore_dir/Caddyfile" "$target_dir/Caddyfile"

caddy validate --config "$target_dir/Caddyfile"

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart caddy
else
    printf '%s\n' 'systemctl is required for a hard Caddy restart.' >&2
    exit 1
fi

printf 'Caddy rolled back from %s\n' "$backup_path"
