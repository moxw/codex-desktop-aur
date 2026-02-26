#!/usr/bin/env bash
set -euo pipefail

PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
SRCINFO_PATH="${SRCINFO_PATH:-.SRCINFO}"
STATE_FILE="${STATE_FILE:-upstream.sha256}"
UPSTREAM_SHA256="${UPSTREAM_SHA256:-}"
PKGVER_CANDIDATE="${PKGVER_CANDIDATE:-}"

if [[ -z "$UPSTREAM_SHA256" ]]; then
  echo "UPSTREAM_SHA256 is required" >&2
  exit 1
fi

if [[ ! -f "$PKGBUILD_PATH" ]]; then
  echo "Missing PKGBUILD at $PKGBUILD_PATH" >&2
  exit 1
fi

current_pkgver="$(awk -F= '/^pkgver=/{print $2; exit}' "$PKGBUILD_PATH")"
current_pkgrel="$(awk -F= '/^pkgrel=/{print $2; exit}' "$PKGBUILD_PATH")"

if [[ -z "$current_pkgver" || -z "$current_pkgrel" ]]; then
  echo "Failed to read current pkgver/pkgrel" >&2
  exit 1
fi

new_pkgver="$current_pkgver"
if [[ -n "$PKGVER_CANDIDATE" ]]; then
  new_pkgver="$PKGVER_CANDIDATE"
fi

if [[ "$new_pkgver" != "$current_pkgver" ]]; then
  new_pkgrel=1
else
  new_pkgrel=$((current_pkgrel + 1))
fi

sed -Ei "s/^pkgver=.*/pkgver=${new_pkgver}/" "$PKGBUILD_PATH"
sed -Ei "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "$PKGBUILD_PATH"

# Keep runtime package.json version aligned with pkgver.
sed -Ei "s/(\"version\": \"[^\"]+\")/\"version\": \"${new_pkgver}\"/" "$PKGBUILD_PATH"

printf '%s\n' "$UPSTREAM_SHA256" > "$STATE_FILE"

printf 'pkgver=%s\n' "$new_pkgver"
printf 'pkgrel=%s\n' "$new_pkgrel"
printf 'state_file=%s\n' "$STATE_FILE"
printf 'srcinfo_path=%s\n' "$SRCINFO_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'pkgver=%s\n' "$new_pkgver"
    printf 'pkgrel=%s\n' "$new_pkgrel"
    printf 'state_file=%s\n' "$STATE_FILE"
    printf 'srcinfo_path=%s\n' "$SRCINFO_PATH"
  } >> "$GITHUB_OUTPUT"
fi
