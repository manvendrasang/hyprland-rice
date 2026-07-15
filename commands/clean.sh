#!/usr/bin/env bash

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
COMMAND_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(dirname "$COMMAND_DIR")"

source "$ROOT_DIR/core/ui.sh"
source "$ROOT_DIR/core/utils.sh"
source "$ROOT_DIR/core/detect.sh"
source "$ROOT_DIR/core/logger.sh"

header
info_log "Started cleanup"

start_time=$(date +%s)

CACHE_PKG=$(directory_size /var/cache/pacman/pkg)
CACHE_USER=$(directory_size ~/.cache)
CACHE_TRASH=$(directory_size ~/.local/share/Trash)
CACHE_JOURNAL=$(journalctl --disk-usage | grep -o '[0-9.]\+[MGK]')

CACHE_PKG=${CACHE_PKG:-0}
CACHE_USER=${CACHE_USER:-0}
CACHE_TRASH=${CACHE_TRASH:-0}

echo

info "Scan Results"

divider

printf "%-24s %12s\n" "Pacman Cache" "$(bytes_to_human "$CACHE_PKG")"
printf "%-24s %12s\n" "User Cache" "$(bytes_to_human "$CACHE_USER")"
printf "%-24s %12s\n" "Trash" "$(bytes_to_human "$CACHE_TRASH")"
printf "%-24s %12s\n" "Journal" "$CACHE_JOURNAL"

divider
echo

confirm "Continue cleanup?"

if [[ $? -ne 0 ]]; then
  warn "Cancelled."
  warn_log "Cleanup cancelled"
  exit 0
fi

echo

info "Cleaning package cache..."

sudo paccache -r >/dev/null

success "Package cache"

info "Cleaning user cache..."

rm -rf ~/.cache/thumbnails
rm -rf ~/.cache/fontconfig
rm -rf ~/.cache/mesa_shader_cache
rm -rf ~/.cache/cliphist

success "User cache"

info "Cleaning trash..."

rm -rf ~/.local/share/Trash/files/*
rm -rf ~/.local/share/Trash/info/*

success "Trash"

info "Cleaning temporary files..."

find /tmp -mindepth 1 -user "$USER" -delete 2>/dev/null || true

success "Temporary files"

info "Vacuuming journals..."

sudo journalctl --vacuum-time=7d >/dev/null

success "Journal"

orphans=$(pacman -Qdtq 2>/dev/null || true)

if [[ -n "$orphans" ]]; then

  echo

  echo "$orphans"

  echo

  confirm "Remove orphan packages?"

  if [[ $? -eq 0 ]]; then
    sudo pacman -Rns $orphans
  fi

fi

echo

info "Refreshing package database..."

case "$PACKAGE_MANAGER" in
yay)
  yay -Sy
  ;;
paru)
  paru -Sy
  ;;
pacman)
  sudo pacman -Sy
  ;;
esac

echo

divider

end_time=$(date +%s)

elapsed=$((end_time - start_time))

success "Cleanup Complete"

success_log "Cleanup completed successfully"

echo

printf "%-24s %s\n" "Elapsed" "${elapsed}s"

printf "%-24s %s\n" "Memory"

free -h

echo

printf "%-24s\n" "Swap"

swapon --show

echo

printf "%-24s\n" "Disk"

df -h /
