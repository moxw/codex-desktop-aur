#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://persistent.oaistatic.com/codex-app-prod/Codex.dmg}"
DMG_PATH="${DMG_PATH:-Codex.dmg}"
WORK_DIR="${WORK_DIR:-work/prepatched}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
PKGVER_CANDIDATE="${PKGVER_CANDIDATE:-}"
CODEX_ELECTRON_TARGET="${CODEX_ELECTRON_TARGET:-}"

NODE_PTY_VER="1.1.0"
BETTER_SQLITE3_VER="12.4.6"
NODE_ADDON_API_PTY_VER="7.1.1"
NODE_ADDON_API_BSQL_VER="8.5.0"

if [[ -z "$CODEX_ELECTRON_TARGET" ]]; then
  echo "CODEX_ELECTRON_TARGET is required (example: 40.2.0)" >&2
  exit 1
fi

if [[ ! -f "$PKGBUILD_PATH" ]]; then
  echo "Missing PKGBUILD at $PKGBUILD_PATH" >&2
  exit 1
fi

current_pkgver="$(awk -F= '/^pkgver=/{print $2; exit}' "$PKGBUILD_PATH")"
if [[ -z "$current_pkgver" ]]; then
  echo "Failed to parse pkgver from $PKGBUILD_PATH" >&2
  exit 1
fi

pkgver="$current_pkgver"
if [[ -n "$PKGVER_CANDIDATE" ]]; then
  pkgver="$PKGVER_CANDIDATE"
fi

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

download_if_missing() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" ]]; then
    return 0
  fi
  local tmp="${out}.tmp"
  rm -f "$tmp"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "$tmp"
  mv "$tmp" "$out"
}

count_occurrences() {
  local needle="$1"
  local file="$2"
  local count
  count="$(LC_ALL=C grep -aobF -- "$needle" "$file" 2>/dev/null | wc -l || true)"
  printf '%s' "${count:-0}"
}

first_offset() {
  local needle="$1"
  local file="$2"
  LC_ALL=C grep -aobF -- "$needle" "$file" 2>/dev/null | cut -d: -f1 | head -n1 || true
}

download_if_missing "$UPSTREAM_URL" "$DMG_PATH"

upstream_sha256="$(sha256sum "$DMG_PATH" | awk '{print $1}')"
short_sha="${upstream_sha256:0:12}"
bundle_name="codex-desktop-prepatched-${pkgver}-${short_sha}-x86_64.tar.gz"
bundle_path="${OUTPUT_DIR}/${bundle_name}"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

codex_dmg_dir="$WORK_DIR/codex-dmg"
payload_root="$WORK_DIR/payload"
mkdir -p "$payload_root/resources"

7z x -y "$DMG_PATH" -o"$codex_dmg_dir" >/dev/null

codex_resources="$codex_dmg_dir/Codex Installer/Codex.app/Contents/Resources"
if [[ ! -f "$codex_resources/app.asar" || ! -d "$codex_resources/app.asar.unpacked" ]]; then
  echo "Failed to locate app.asar payload in DMG extraction output." >&2
  exit 1
fi

install -Dm644 "$codex_resources/app.asar" "$payload_root/resources/app.asar"
cp -a "$codex_resources/app.asar.unpacked" "$payload_root/resources/"

asar_path="$payload_root/resources/app.asar"
patched_menu_bar=0

hard_old='S.removeMenu()'
hard_new='S.on("show",N)'
hard_old_hits="$(count_occurrences "$hard_old" "$asar_path")"
hard_new_hits="$(count_occurrences "$hard_new" "$asar_path")"

if [[ "$hard_old_hits" -eq 1 && "$hard_new_hits" -eq 0 ]]; then
  hard_off="$(first_offset "$hard_old" "$asar_path")"
  printf '%s' "$hard_new" | dd of="$asar_path" bs=1 seek="$hard_off" conv=notrunc status=none
fi

for old in \
  'S.isDestroyed()||S.setTitle(S.getTitle())' \
  'E.isDestroyed()||E.setTitle(E.getTitle())'
do
  if [[ "$old" == S* ]]; then
    new='S.isDestroyed()||S.setAutoHideMenuBar(!0)'
  else
    new='E.isDestroyed()||E.setAutoHideMenuBar(!0)'
  fi

  if [[ ${#old} -ne ${#new} ]]; then
    continue
  fi

  old_hits="$(count_occurrences "$old" "$asar_path")"
  new_hits="$(count_occurrences "$new" "$asar_path")"

  if [[ "$old_hits" -eq 1 ]]; then
    patch_off="$(first_offset "$old" "$asar_path")"
    printf '%s' "$new" | dd of="$asar_path" bs=1 seek="$patch_off" conv=notrunc status=none
    patched_menu_bar=1
    break
  fi

  if [[ "$old_hits" -eq 0 && "$new_hits" -eq 1 ]]; then
    patched_menu_bar=1
    break
  fi
done

if [[ "$patched_menu_bar" -eq 0 ]]; then
  echo "WARNING: Menu-bar patch anchor not found; shipping upstream app.asar unchanged." >&2
fi

download_if_missing "https://registry.npmjs.org/node-pty/-/node-pty-${NODE_PTY_VER}.tgz" "node-pty-${NODE_PTY_VER}.tgz"
download_if_missing "https://registry.npmjs.org/better-sqlite3/-/better-sqlite3-${BETTER_SQLITE3_VER}.tgz" "better-sqlite3-${BETTER_SQLITE3_VER}.tgz"
download_if_missing "https://registry.npmjs.org/node-addon-api/-/node-addon-api-${NODE_ADDON_API_PTY_VER}.tgz" "node-addon-api-${NODE_ADDON_API_PTY_VER}.tgz"
download_if_missing "https://registry.npmjs.org/node-addon-api/-/node-addon-api-${NODE_ADDON_API_BSQL_VER}.tgz" "node-addon-api-${NODE_ADDON_API_BSQL_VER}.tgz"

nodepty_src="$WORK_DIR/nodepty-src"
bsql_src="$WORK_DIR/bsql-src"

mkdir -p "$nodepty_src" "$bsql_src"
bsdtar -xf "node-pty-${NODE_PTY_VER}.tgz" -C "$nodepty_src" --strip-components=1
mkdir -p "$nodepty_src/node_modules/node-addon-api"
bsdtar -xf "node-addon-api-${NODE_ADDON_API_PTY_VER}.tgz" -C "$nodepty_src/node_modules/node-addon-api" --strip-components=1

bsdtar -xf "better-sqlite3-${BETTER_SQLITE3_VER}.tgz" -C "$bsql_src" --strip-components=1
mkdir -p "$bsql_src/node_modules/node-addon-api"
bsdtar -xf "node-addon-api-${NODE_ADDON_API_BSQL_VER}.tgz" -C "$bsql_src/node_modules/node-addon-api" --strip-components=1

gyp_env=(
  PYTHON="${PYTHON:-/usr/bin/python3}"
  npm_config_runtime=electron
  npm_config_target="$CODEX_ELECTRON_TARGET"
  npm_config_disturl=https://electronjs.org/headers
  npm_config_build_from_source=true
)

(cd "$nodepty_src" && env "${gyp_env[@]}" node-gyp rebuild -j max)
(cd "$bsql_src" && env "${gyp_env[@]}" node-gyp rebuild -j max)

install -Dm755 "$nodepty_src/build/Release/pty.node" \
  "$payload_root/resources/app.asar.unpacked/node_modules/node-pty/build/Release/pty.node"
install -Dm755 "$bsql_src/build/Release/better_sqlite3.node" \
  "$payload_root/resources/app.asar.unpacked/node_modules/better-sqlite3/build/Release/better_sqlite3.node"

rm -f "$bundle_path"
tar -C "$payload_root" -czf "$bundle_path" resources

bundle_sha256="$(sha256sum "$bundle_path" | awk '{print $1}')"

printf 'bundle_name=%s\n' "$bundle_name"
printf 'bundle_path=%s\n' "$bundle_path"
printf 'bundle_sha256=%s\n' "$bundle_sha256"
printf 'pkgver=%s\n' "$pkgver"
printf 'upstream_sha256=%s\n' "$upstream_sha256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'bundle_name=%s\n' "$bundle_name"
    printf 'bundle_path=%s\n' "$bundle_path"
    printf 'bundle_sha256=%s\n' "$bundle_sha256"
    printf 'pkgver=%s\n' "$pkgver"
    printf 'upstream_sha256=%s\n' "$upstream_sha256"
  } >> "$GITHUB_OUTPUT"
fi
