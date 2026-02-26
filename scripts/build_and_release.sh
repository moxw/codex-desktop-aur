#!/usr/bin/env bash
set -euo pipefail

PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
PKG_FILES_GLOB="${PKG_FILES_GLOB:-*.pkg.tar.zst}"
UPSTREAM_SHA256="${UPSTREAM_SHA256:-}"
DRY_RUN="${DRY_RUN:-false}"

if [[ "$DRY_RUN" != "true" && -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN is required for release operations" >&2
  exit 1
fi

pkgver="$(awk -F= '/^pkgver=/{print $2; exit}' "$PKGBUILD_PATH")"
if [[ -z "$pkgver" ]]; then
  echo "Failed to parse pkgver from $PKGBUILD_PATH" >&2
  exit 1
fi

short_sha="${UPSTREAM_SHA256:0:12}"
if [[ -z "$short_sha" ]]; then
  short_sha="manual"
fi

release_tag="codex-desktop-bin-${pkgver}-${short_sha}"
release_title="codex-desktop-bin ${pkgver} (${short_sha})"

mapfile -t pkg_files < <(ls -1 $PKG_FILES_GLOB)
if [[ "${#pkg_files[@]}" -eq 0 ]]; then
  echo "No package artifacts found matching: $PKG_FILES_GLOB" >&2
  exit 1
fi

sha_file="sha256sums.txt"
sha256sum "${pkg_files[@]}" > "$sha_file"

release_notes="Automated build for pkgver ${pkgver}."
if [[ -n "$UPSTREAM_SHA256" ]]; then
  release_notes+=$'\n\nUpstream DMG SHA256: '
  release_notes+="$UPSTREAM_SHA256"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN=true, skipping GitHub release create/upload."
  echo "Would publish tag: $release_tag"
  echo "Would upload files: ${pkg_files[*]} $sha_file"
else
  if gh release view "$release_tag" >/dev/null 2>&1; then
    gh release upload "$release_tag" "${pkg_files[@]}" "$sha_file" --clobber
  else
    gh release create "$release_tag" "${pkg_files[@]}" "$sha_file" \
      --title "$release_title" \
      --notes "$release_notes"
  fi
fi

printf 'release_tag=%s\n' "$release_tag"
printf 'release_assets=%s\n' "${pkg_files[*]} $sha_file"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'release_tag=%s\n' "$release_tag"
    printf 'release_assets=%s\n' "${pkg_files[*]} $sha_file"
  } >> "$GITHUB_OUTPUT"
fi
