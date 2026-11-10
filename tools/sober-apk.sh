#!/usr/bin/env bash
# sober-apk.sh - inspect, back up and swap Sober's Android package safely.
#
# Sober runs Roblox's Android build: base.apk plus split_config.x86_64.apk
# inside the user-writable data directory. Replacing those files is how a
# patched client is installed. This tool never downloads anything - you supply
# the package, it verifies the architecture, keeps the original and can put it
# back.
#
#   ./sober-apk.sh status
#   ./sober-apk.sh backup
#   ./sober-apk.sh install ~/Downloads/client.apk [--force]
#   ./sober-apk.sh install ~/Downloads/client.apkm
#   ./sober-apk.sh restore
#   ./sober-apk.sh backups

set -Eeuo pipefail

SOBER_ID="org.vinegarhq.Sober"
PKG="$HOME/.var/app/$SOBER_ID/data/sober/packages/x86_64/com.roblox.client"
STORE="${XDG_DATA_HOME:-$HOME/.local/share}/fisch-hub/apk-backup"
BASE="$PKG/base.apk"
SPLIT="$PKG/split_config.x86_64.apk"

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s  ok%s   %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s  !!%s   %s\n' "$c_yellow" "$c_reset" "$*"; }
die()  { printf '%s  xx%s   %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
need unzip
need sha256sum

sober_running() { pgrep -f "bwrap.*sober" >/dev/null 2>&1; }

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }

describe() {
  local file="$1" label="$2"
  if [ ! -f "$file" ]; then
    warn "$label missing: $file"
    return 0
  fi
  local size sha when
  size=$(stat -c %s "$file")
  sha=$(sha256sum "$file" | cut -c1-16)
  when=$(stat -c %y "$file" | cut -d. -f1)
  printf '  %-8s %10s  %s  %s\n' "$label" "$(human "$size")" "$sha" "$when"
}

cmd_status() {
  say "sober package"
  say "$c_dim$PKG$c_reset"
  describe "$BASE" "base"
  describe "$SPLIT" "x86_64"
  if sober_running; then
    warn "sober is running"
  else
    ok "sober not running"
  fi
  if [ -d "$STORE" ] && [ -n "$(ls -A "$STORE" 2>/dev/null)" ]; then
    say "  backups  $(ls -1 "$STORE" | wc -l) in $STORE"
  else
    say "  backups  none"
  fi
}

cmd_backup() {
  [ -f "$BASE" ] || die "no base.apk to back up"
  local stamp dir
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="$STORE/$stamp"
  mkdir -p "$dir"
  cp -p "$BASE" "$dir/base.apk"
  [ -f "$SPLIT" ] && cp -p "$SPLIT" "$dir/split_config.x86_64.apk"
  sha256sum "$dir"/* > "$dir/CHECKSUMS"
  ok "backed up to $dir"
}

cmd_backups() {
  [ -d "$STORE" ] || { say "no backups"; return 0; }
  for dir in "$STORE"/*; do
    [ -d "$dir" ] || continue
    printf '  %s  ' "$(basename "$dir")"
    du -sh "$dir" 2>/dev/null | cut -f1
  done
}

# A split carries the engine; a base carries the manifest. .apkm is just a zip
# of splits, so the same inspection works on all three.
inspect_zip() {
  local file="$1"
  unzip -l "$file" >/dev/null 2>&1 || die "not a zip/apk: $file"
  local listing
  listing=$(unzip -l "$file" 2>/dev/null)
  local kind="unknown"
  if grep -q 'lib/x86_64/libroblox\.so' <<<"$listing"; then kind="split"
  elif grep -q 'AndroidManifest\.xml' <<<"$listing"; then kind="base"
  elif grep -q 'split_config\.x86_64\.apk' <<<"$listing"; then kind="bundle"
  fi
  local arch_ok=0
  grep -q 'lib/arm64-v8a/' <<<"$listing" && arch_ok=1
  grep -q 'lib/x86_64/' <<<"$listing" && arch_ok=0
  [ "$arch_ok" -eq 0 ] || die "this package contains arm64 libraries, Sober needs x86_64"
  printf '%s' "$kind"
}

extract_bundle() {
  local file="$1" work="$2"
  mkdir -p "$work"
  unzip -o -q "$file" -d "$work"
  find "$work" -maxdepth 3 -type f \( -name '*.apk' -o -name '*.apks' \) | while read -r part; do
    case "$(basename "$part")" in
      base.apk|base-*.apk) cp -f "$part" "$work/base.apk" ;;
      *x86_64*.apk)        cp -f "$part" "$work/split_config.x86_64.apk" ;;
    esac
  done
}

cmd_install() {
  local input="${1:-}"
  local force="${2:-}"
  [ -n "$input" ] || die "usage: $0 install <file.apk|file.apkm> [--force]"
  [ -f "$input" ] || die "no such file: $input"

  local kind
  kind=$(inspect_zip "$input")
  case "$kind" in
    base|split|bundle) ok "package type: $kind" ;;
    *) die "cannot tell what this is - expected a base, a split, or an .apkm bundle" ;;
  esac

  if sober_running && [ "$force" != "--force" ]; then
    die "close Sober first (or pass --force). Files are open while it runs."
  fi

  local stage
  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT

  local new_base="" new_split=""
  if [ "$kind" = "bundle" ]; then
    extract_bundle "$input" "$stage"
    new_base="$stage/base.apk"
    new_split="$stage/split_config.x86_64.apk"
    [ -f "$new_base" ] || new_base=""
    [ -f "$new_split" ] || new_split=""
  elif [ "$kind" = "base" ]; then
    new_base="$input"
  else
    new_split="$input"
  fi

  if [ -z "$new_base" ] && [ -z "$new_split" ]; then
    die "nothing recognisable to install"
  fi

  cmd_backup

  if [ -n "$new_base" ]; then
    cp -f "$new_base" "$BASE.new"
    mv -f "$BASE.new" "$BASE"
    ok "installed base.apk"
  fi
  if [ -n "$new_split" ]; then
    cp -f "$new_split" "$SPLIT.new"
    mv -f "$SPLIT.new" "$SPLIT"
    ok "installed split_config.x86_64.apk"
  fi

  say ""
  say "  launch Sober to test. If it fails, run: $0 restore"
}

cmd_restore() {
  [ -d "$STORE" ] || die "no backups in $STORE"
  local latest
  latest=$(ls -1d "$STORE"/*/ 2>/dev/null | sort | tail -1)
  [ -n "$latest" ] || die "no backups in $STORE"
  if sober_running; then die "close Sober first"; fi
  [ -f "$latest/base.apk" ] && cp -f "$latest/base.apk" "$BASE"
  [ -f "$latest/split_config.x86_64.apk" ] && cp -f "$latest/split_config.x86_64.apk" "$SPLIT"
  ok "restored $(basename "$latest")"
}

case "${1:-status}" in
  status)  cmd_status ;;
  backup)  cmd_backup ;;
  backups) cmd_backups ;;
  install) shift; cmd_install "$@" ;;
  restore) cmd_restore ;;
  *) say "usage: $0 [status|backup|backups|install <file> [--force]|restore]"; exit 2 ;;
esac
