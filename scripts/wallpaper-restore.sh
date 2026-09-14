#!/usr/bin/env bash

########################################
# Startup wallpaper restore, with a
# first-run fallback
########################################
#
# "waypaper --restore" only ever applies
# the LAST wallpaper chosen through the
# waypaper GUI (confirmed in waypaper's own
# docs: "--restore - sets the last chosen
# wallpaper") - it has nothing to restore
# until you've picked one at least once via
# SUPER+W. That's exactly why nothing loads
# automatically on a completely fresh
# install, even though it then works
# correctly on every login after that first
# manual pick.
#
# Falls back to "--random" (also a real,
# documented waypaper flag) for that one
# first run, so something loads from your
# wallpaper folder without needing to open
# waypaper manually first.
#

CONFIG_FILE="${HYPRX_TARGET_HOME:-$HOME}/.config/waypaper/config.ini"

if [[ -f "$CONFIG_FILE" ]] && grep -qE '^wallpaper[[:space:]]*=[[:space:]]*\S' "$CONFIG_FILE"; then
	waypaper --restore
else
	waypaper --random
fi
