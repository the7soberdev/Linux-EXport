#!/usr/bin/env bash
# Fisch Hub - one launcher that installs, syncs, verifies, watches and starts.
#
#   fisch-hub                 install if needed, sync, watch, launch Sober
#   fisch-hub --status        what is installed, what is detected, what is missing
#   fisch-hub --sync          copy the hub into every autoexec directory now
#   fisch-hub --verify        compare every installed copy against the source
#   fisch-hub --install       place this launcher + desktop entry, then sync
#   fisch-hub --no-launch     do everything except start Sober
#   fisch-hub --uninstall     remove launcher, desktop entry and all copies
#
# The watcher is the part that makes delivery reliable: executor folders are
# often created on first run, after this script starts. It polls once a second
# for the whole session and copies the hub into any directory that appears, so
# a late-created workspace still gets the hub before the first injection.

set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$SELF")" && pwd)"
CONFIG_DIR="${FISCHHUB_CONFIG:-$HOME/.config/fisch-hub}"
HUB="$CONFIG_DIR/FischHub.lua"
LOADER="$CONFIG_DIR/loader.lua"
LOCAL_BIN="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
DESKTOP="$APP_DIR/fisch-hub.desktop"
SOBER_ID="org.vinegarhq.Sober"

# Executor binaries that ship a Linux build and are commonly paired with Sober.
EXECUTOR_NAMES=(volt wave solara delta synx nihon watermelon macsploit arcadia
                hydrogen fluxus axiom celestia nightmare swift)

#  --------------------------------------------------------------- output

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_good=$'\033[32m'; c_warn=$'\033[33m'
c_bad=$'\033[31m'; c_bold=$'\033[1m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '  %sok%s   %s\n' "$c_good" "$c_reset" "$*"; }
warn() { printf '  %s!!%s   %s\n' "$c_warn" "$c_reset" "$*"; }
bad()  { printf '  %sxx%s   %s\n' "$c_bad" "$c_reset" "$*"; }
section() { printf '\n%s%s%s\n' "$c_bold" "$*" "$c_reset"; }

die() { bad "$*"; exit 1; }

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Fisch Hub" "Fisch Hub" "$*" >/dev/null 2>&1 || true
  fi
}

#  --------------------------------------------------------------- discovery

autoexec_dirs() {
  local pattern
  {
    for pattern in \
      "$HOME/.local/share"/*/autoexec \
      "$HOME/.local/share"/*/workspace \
      "$HOME/.config"/*/autoexec \
      "$HOME/.var/app"/*/data/*/autoexec \
      "$HOME/.var/app"/*/data/*/workspace \
      "$HOME/.wine/drive_c/users"/*/AppData/Local/*/autoexec \
      "$HOME/.wine/drive_c/users"/*/AppData/Roaming/*/autoexec
    do
      if [ -d "$pattern" ]; then printf '%s\n' "$pattern"; fi
    done
  } | awk 'NF && !seen[$0]++' || true
  return 0
}

find_executors() {
  local name found=0 apps="" app
  for name in "${EXECUTOR_NAMES[@]}"; do
    if command -v "$name" >/dev/null 2>&1; then
      printf '  binary   %s -> %s\n' "$name" "$(command -v "$name")"
      found=1
    fi
  done
  if command -v flatpak >/dev/null 2>&1; then
    apps="$(flatpak list --app --columns=application 2>/dev/null || true)"
    for name in "${EXECUTOR_NAMES[@]}"; do
      app="$(printf '%s\n' "$apps" | grep -i -- "$name" | head -n1 || true)"
      if [ -n "$app" ]; then
        printf '  flatpak  %s\n' "$app"
        found=1
      fi
    done
  fi
  if [ "$found" -eq 1 ]; then return 0; fi
  return 1
}

#  --------------------------------------------------------------- transfer

hash_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

sync_into() {
  local dir="$1"
  local target_hash
  mkdir -p "$dir/fischhub"

  target_hash="$(hash_of "$HUB")"

  local dest
  for dest in "$dir/fischhub/hub.lua" "$dir/FischHub.lua"; do
    if [ "$(hash_of "$dest")" != "$target_hash" ]; then
      cp -f "$HUB" "$dest"
    fi
    if [ "$(hash_of "$dest")" != "$target_hash" ]; then
      bad "copy failed: $dest"
      return 1
    fi
  done

  for dest in "$dir/000-fischhub.lua" "$dir/fischhub-loader.lua"; do
    if [ "$(hash_of "$dest")" != "$(hash_of "$LOADER")" ]; then
      cp -f "$LOADER" "$dest"
    fi
  done

  ok "$dir"
  return 0
}

cmd_sync() {
  local d count=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    sync_into "$d" && count=$((count + 1))
  done < <(autoexec_dirs)
  printf '  %d director%s synced\n' "$count" "$([ "$count" -eq 1 ] && echo y || echo ies)"
  return 0
}

cmd_verify() {
  local d count=0 failed=0
  local target_hash; target_hash="$(hash_of "$HUB")"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    count=$((count + 1))
    local copy
    for copy in "$d/fischhub/hub.lua" "$d/FischHub.lua"; do
      if [ ! -f "$copy" ]; then
        bad "missing  $copy"; failed=1
      elif [ "$(hash_of "$copy")" != "$target_hash" ]; then
        bad "stale    $copy"; failed=1
      fi
    done
    [ "$failed" -eq 0 ] && ok "match  $d"
  done < <(autoexec_dirs)
  return "$failed"
}

#  --------------------------------------------------------------- watcher

WATCH_PID=""
start_watcher() {
  (
    declare -A known=()
    local d
    while :; do
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        if [ "${known[$d]:-}" != "1" ]; then
          known[$d]=1
          sync_into "$d" >/dev/null 2>&1
          printf '  %s+%s   new folder adopted: %s\n' "$c_good" "$c_reset" "$d"
        fi
      done < <(autoexec_dirs)
      sleep 1
    done
  ) &
  WATCH_PID=$!
}

stop_watcher() {
  if [ -n "${WATCH_PID:-}" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
  fi
}

#  --------------------------------------------------------------- setup

ensure_source() {
  if [ -f "$REPO/dist/FischHub.lua" ]; then
    mkdir -p "$CONFIG_DIR"
    cp -f "$REPO/dist/FischHub.lua" "$HUB"
    cp -f "$REPO/autoload/loader.lua" "$LOADER"
  fi
  [ -f "$HUB" ] || die "no hub source: $HUB"
  [ -f "$LOADER" ] || die "no loader: $LOADER"
}

install_launcher() {
  mkdir -p "$LOCAL_BIN"
  if [ "$SELF" != "$LOCAL_BIN/fisch-hub" ]; then
    cp -f "$SELF" "$LOCAL_BIN/fisch-hub"
    chmod +x "$LOCAL_BIN/fisch-hub"
  fi
  ok "launcher  $LOCAL_BIN/fisch-hub"

  mkdir -p "$APP_DIR"
  local icon
  icon="$(find /var/lib/flatpak/exports/share/icons "$HOME/.local/share/flatpak/exports/share/icons" \
    -name '*sober*' 2>/dev/null | head -n1 || true)"
  cat > "$DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Sober (Fisch Hub)
Comment=Roblox via Sober with the Fisch Hub autoloader
Exec=$LOCAL_BIN/fisch-hub %U
Icon=${icon:-applications-games}
Terminal=true
Categories=Game;
StartupWMClass=sober
DESKTOP_EOF
  ok "desktop   $DESKTOP"
}

prime_clipboard() {
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$HUB" && ok "hub copied to clipboard - press Ctrl+V in the executor"
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$HUB" && ok "hub copied to clipboard - press Ctrl+V in the executor"
  elif command -v xsel >/dev/null 2>&1; then
    xsel --clipboard --input < "$HUB" && ok "hub copied to clipboard - press Ctrl+V in the executor"
  else
    warn "no clipboard tool - open $HUB and copy it manually"
  fi
}

#  --------------------------------------------------------------- commands

cmd_status() {
  section "source"
  if [ -f "$HUB" ]; then
    ok "$HUB ($(wc -c < "$HUB") bytes)"
  else
    bad "missing $HUB - run: $0 --install"
  fi

  section "delivery targets"
  local dirs; dirs="$(autoexec_dirs)"
  if [ -z "$dirs" ]; then
    warn "none yet. The watcher adopts them the moment an executor creates one."
  else
    printf '%s\n' "$dirs" | sed 's/^/  ->  /'
  fi

  section "executors"
  if find_executors; then :; else
    warn "no executor binary found"
  fi

  section "game"
  if command -v flatpak >/dev/null 2>&1 && flatpak info "$SOBER_ID" >/dev/null 2>&1; then
    ok "Sober installed ($SOBER_ID)"
  else
    bad "Sober not installed"
  fi
}

cmd_run() {
  local launch=1
  [ "${1:-}" = "--no-launch" ] && launch=0

  section "fisch hub"
  ensure_source
  ok "source    $HUB"

  install_launcher
  cmd_sync

  if [ "$launch" -eq 1 ]; then
    section "launch"
    start_watcher
    trap 'stop_watcher' EXIT INT TERM

    if ! find_executors >/dev/null; then
      warn "no executor detected"
      cat <<'WHY'
  Sober runs Roblox's *Android* build, not the Windows client. There is no
  autoexec folder to drop a script into, which is the only thing this launcher
  knows how to use.

  Hacks on Sober are real, but they arrive by another door: a patched package
  (base.apk + split_config.x86_64.apk, both user-writable) or an injector
  attached to libroblox.so. Either one gives you an executor with its own
  script box; paste the loader there and the hub starts.

  tools/sober-apk.sh backups, verifies and swaps a package with a restore path.
WHY
      notify "No Lua runtime in Sober. Hub staged, cannot load."
      prime_clipboard
    else
      notify "Hub synced. Starting Sober."
    fi
    ok "watching for new autoexec folders"
    printf '\n'

    if ! flatpak info "$SOBER_ID" >/dev/null 2>&1; then
      die "Sober not installed"
    fi
    flatpak run "$SOBER_ID" "${@:2}" || true
    stop_watcher
    say ""
    ok "Sober closed"
  else
    section "done (not launching)"
    cmd_verify || true
  fi
}

cmd_watch() {
  ensure_source
  section "watching for executor folders"
  start_watcher
  trap 'stop_watcher' EXIT INT TERM
  ok "polling every second - Ctrl-C to stop"
  while :; do sleep 5; done
}

cmd_install() {
  section "installing"
  ensure_source
  install_launcher
  cmd_sync
  section "verify"
  cmd_verify || true
  section "next"
  say "  run: $LOCAL_BIN/fisch-hub"
  say "  or launch 'Sober (Fisch Hub)' from your app menu"
}

cmd_uninstall() {
  section "removing"
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    rm -rf "$d/fischhub" "$d/FischHub.lua" "$d/000-fischhub.lua" "$d/fischhub-loader.lua"
    ok "cleaned $d"
  done < <(autoexec_dirs)
  rm -f "$LOCAL_BIN/fisch-hub" "$DESKTOP"
  rm -rf "$CONFIG_DIR"
  ok "removed launcher, desktop entry, source"
}

case "${1:-}" in
  --status)    cmd_status ;;
  --sync)      ensure_source; section "sync"; cmd_sync ;;
  --verify)    section "verify"; cmd_verify ;;
  --install)   cmd_install ;;
  --uninstall) cmd_uninstall ;;
  --no-launch) cmd_run --no-launch ;;
  --watch)     cmd_watch ;;
  -h|--help)   sed -n '2,17p' "$SELF" | sed 's/^# \{0,1\}//' ;;
  "")          cmd_run ;;
  *)           die "unknown option: $1 (try --help)" ;;
esac
