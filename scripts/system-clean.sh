#!/usr/bin/env bash

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

echo -e "${BLUE}"
echo "=========================================="
echo "        Hyprland Rice Maintenance"
echo "=========================================="
echo -e "${RESET}"

echo -e "${YELLOW}Disk usage before:${RESET}"
df -h /

echo
echo -e "${GREEN}Cleaning package cache...${RESET}"
sudo paccache -r

echo
echo -e "${GREEN}Cleaning user cache...${RESET}"

rm -rf \
    "$HOME/.cache/thumbnails" \
    "$HOME/.cache/fontconfig" \
    "$HOME/.cache/mesa_shader_cache" \
    "$HOME/.cache/cliphist"

echo
echo -e "${GREEN}Cleaning temporary files...${RESET}"

find /tmp -mindepth 1 -user "$USER" -delete 2>/dev/null || true

rm -rf \
    "$HOME/.local/share/Trash/files/"* \
    "$HOME/.local/share/Trash/info/"*

echo
echo -e "${GREEN}Vacuuming system logs...${RESET}"

sudo journalctl --vacuum-time=7d

echo
echo -e "${GREEN}Removing orphan packages...${RESET}"

orphans=$(pacman -Qdtq || true)

if [[ -n "$orphans" ]]; then
    sudo pacman -Rns --noconfirm $orphans
else
    echo "No orphan packages."
fi

echo
echo -e "${GREEN}Refreshing package databases...${RESET}"

if command -v yay >/dev/null 2>&1; then
    yay -Syy >/dev/null
elif command -v paru >/dev/null 2>&1; then
    paru -Syy >/dev/null
else
    sudo pacman -Syy >/dev/null
fi

echo
echo -e "${GREEN}Checking failed services...${RESET}"

systemctl --failed || true

echo
echo -e "${GREEN}Memory status:${RESET}"

free -h

echo
echo -e "${GREEN}Swap status:${RESET}"

swapon --show

echo
echo -e "${YELLOW}Disk usage after:${RESET}"

df -h /

echo
echo -e "${GREEN}Maintenance complete.${RESET}"