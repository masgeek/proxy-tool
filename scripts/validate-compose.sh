#!/usr/bin/env bash
#
# Render every stack's Compose file to catch syntax errors, bad interpolation and
# missing required variables before they reach a host.
#
# This never contacts a Docker daemon: `docker compose config` only parses and
# interpolates. It is therefore safe in CI and on a laptop.
#
# Secrets are never read. A stack's real .env is used when present, because that
# is what will actually be deployed; otherwise .env.example is used. Empty
# values are replaced with a placeholder, and any variable the renderer still
# reports as missing is injected with a placeholder and the render retried. That
# handles stacks whose .env.example leaves a required variable blank without
# having to maintain a list of them here.
#
# Usage: scripts/validate-compose.sh [stack ...]
#   With no arguments every stack under stacks/ is checked.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACEHOLDER="ci-placeholder-value"
MAX_ATTEMPTS=8
failures=0
checked=0

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is not installed" >&2
  exit 127
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "error: the docker compose plugin is not available" >&2
  exit 127
fi

compose_version="$(docker compose version --short 2>/dev/null || echo unknown)"

# `extends` needs a fairly recent Compose, and include is newer still.
# `docker compose version --short` prints a leading "v", which must be stripped
# before the comparison or bash evaluates "v2" as 0.
major="${compose_version#v}"
major="${major%%.*}"
if [[ ! "$major" =~ ^[0-9]+$ || "$major" -lt 2 ]]; then
  echo "warning: docker compose ${compose_version} is older than 2.x; some stacks may not render" >&2
fi

render_stack() {
  local dir="$1"
  local name="$2"
  local compose="$dir/docker-compose.yml"
  local env_src="$dir/.env"
  local env_file
  local output attempt missing injected

  [[ -f "$compose" ]] || return 0

  [[ -f "$env_src" ]] || env_src="$dir/.env.example"
  env_file="$(mktemp)"

  if [[ -f "$env_src" ]]; then
    # Fill in blanks so a value-less placeholder line does not read as "unset".
    sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)=[[:space:]]*$/\1='"$PLACEHOLDER"'/' \
      "$env_src" >"$env_file"
  else
    : >"$env_file"
    echo "  note: ${name} has no .env or .env.example; relying on Compose defaults only"
  fi

  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if output="$(docker compose --env-file "$env_file" -f "$compose" config --quiet 2>&1)"; then
      printf '  ok    %-14s (env: %s)\n' "$name" "$(basename "$env_src")"
      rm -f "$env_file"
      return 0
    fi

    # Compose reports: required variable FOO is missing a value
    missing="$(printf '%s\n' "$output" |
      grep -oE 'required variable [A-Za-z_][A-Za-z0-9_]* is missing a value' |
      awk '{print $3}' | sort -u)"

    if [[ -z "$missing" ]]; then
      printf '  FAIL  %-14s\n' "$name"
      printf '%s\n' "$output" | sed 's/^/        /'
      rm -f "$env_file"
      return 1
    fi

    injected=""
    while read -r var; do
      [[ -n "$var" ]] || continue
      printf '%s=%s\n' "$var" "$PLACEHOLDER" >>"$env_file"
      injected="$injected $var"
    done <<<"$missing"

    echo "  note: ${name} needs${injected}, injected a placeholder"
  done

  printf '  FAIL  %-14s (gave up after %d attempts)\n' "$name" "$MAX_ATTEMPTS"
  printf '%s\n' "$output" | sed 's/^/        /'
  rm -f "$env_file"
  return 1
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  while IFS= read -r dir; do
    targets+=("$(basename "$dir")")
  done < <(find "$ROOT/stacks" -mindepth 1 -maxdepth 1 -type d | sort)
fi

echo "docker compose ${compose_version}"
for name in "${targets[@]}"; do
  dir="$ROOT/stacks/$name"
  if [[ ! -d "$dir" ]]; then
    echo "  FAIL  ${name} (no such stack directory)"
    failures=$((failures + 1))
    continue
  fi
  checked=$((checked + 1))
  if ! render_stack "$dir" "$name"; then
    failures=$((failures + 1))
  fi
done

echo
if [[ $failures -gt 0 ]]; then
  echo "${failures} of ${checked} stacks failed to render"
  exit 1
fi

echo "all ${checked} stacks rendered"
