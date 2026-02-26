#!/usr/bin/env bash
set -euo pipefail

PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
SRCINFO_PATH="${SRCINFO_PATH:-.SRCINFO}"
STATE_FILE="${STATE_FILE:-upstream.sha256}"
UPSTREAM_SHA256="${UPSTREAM_SHA256:-}"
PKGVER_CANDIDATE="${PKGVER_CANDIDATE:-}"
PREPATCHED_SHA256="${PREPATCHED_SHA256:-}"
RELEASE_REPO="${RELEASE_REPO:-}"

if [[ -z "$UPSTREAM_SHA256" ]]; then
  echo "UPSTREAM_SHA256 is required" >&2
  exit 1
fi

if [[ -z "$PREPATCHED_SHA256" ]]; then
  echo "PREPATCHED_SHA256 is required" >&2
  exit 1
fi

if [[ ! -f "$PKGBUILD_PATH" ]]; then
  echo "Missing PKGBUILD at $PKGBUILD_PATH" >&2
  exit 1
fi

current_pkgver="$(awk -F= '/^pkgver=/{print $2; exit}' "$PKGBUILD_PATH")"
current_pkgrel="$(awk -F= '/^pkgrel=/{print $2; exit}' "$PKGBUILD_PATH")"
current_release_repo="$(awk -F"'" '/^_release_repo=/{print $2; exit}' "$PKGBUILD_PATH")"

if [[ -z "$current_pkgver" || -z "$current_pkgrel" ]]; then
  echo "Failed to read current pkgver/pkgrel" >&2
  exit 1
fi

if [[ -z "$RELEASE_REPO" ]]; then
  RELEASE_REPO="$current_release_repo"
fi

if [[ -z "$RELEASE_REPO" ]]; then
  echo "RELEASE_REPO is required (and _release_repo is missing in PKGBUILD)." >&2
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

short_sha="${UPSTREAM_SHA256:0:12}"
release_tag="codex-desktop-bin-${new_pkgver}-${short_sha}"
bundle_name="codex-desktop-prepatched-${new_pkgver}-${short_sha}-x86_64.tar.gz"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

release_repo_escaped="$(escape_sed_replacement "$RELEASE_REPO")"
release_tag_escaped="$(escape_sed_replacement "$release_tag")"
bundle_name_escaped="$(escape_sed_replacement "$bundle_name")"
prepatched_sha_escaped="$(escape_sed_replacement "$PREPATCHED_SHA256")"
new_pkgver_escaped="$(escape_sed_replacement "$new_pkgver")"

sed -Ei "s/^pkgver=.*/pkgver=${new_pkgver}/" "$PKGBUILD_PATH"
sed -Ei "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "$PKGBUILD_PATH"
sed -Ei "s/^_release_repo=.*/_release_repo='${release_repo_escaped}'/" "$PKGBUILD_PATH"
sed -Ei "s/^_release_tag=.*/_release_tag='${release_tag_escaped}'/" "$PKGBUILD_PATH"
sed -Ei "s/^_bundle_name=.*/_bundle_name='${bundle_name_escaped}'/" "$PKGBUILD_PATH"
sed -Ei "/^sha256sums=\(/,/^\)/{0,/^[[:space:]]*'[^']*'[[:space:]]*$/{s//  '${prepatched_sha_escaped}'/}}" "$PKGBUILD_PATH"

# Keep runtime package.json version aligned with pkgver.
sed -Ei "s/(\"version\": \"[^\"]+\")/\"version\": \"${new_pkgver_escaped}\"/" "$PKGBUILD_PATH"

printf '%s\n' "$UPSTREAM_SHA256" > "$STATE_FILE"

printf 'pkgver=%s\n' "$new_pkgver"
printf 'pkgrel=%s\n' "$new_pkgrel"
printf 'release_tag=%s\n' "$release_tag"
printf 'bundle_name=%s\n' "$bundle_name"
printf 'state_file=%s\n' "$STATE_FILE"
printf 'srcinfo_path=%s\n' "$SRCINFO_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'pkgver=%s\n' "$new_pkgver"
    printf 'pkgrel=%s\n' "$new_pkgrel"
    printf 'release_tag=%s\n' "$release_tag"
    printf 'bundle_name=%s\n' "$bundle_name"
    printf 'state_file=%s\n' "$STATE_FILE"
    printf 'srcinfo_path=%s\n' "$SRCINFO_PATH"
  } >> "$GITHUB_OUTPUT"
fi
