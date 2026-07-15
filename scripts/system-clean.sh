#!/usr/bin/env bash

set -e

GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
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

rm -rf ~/.cache/thumbnails
rm -rf ~/.cache/fontconfig
rm -rf ~/.cache/mesa_shader_cache
rm -rf ~/.cache/cliphist

echo
echo -e "${GREEN}Cleaning temporary files...${RESET}"

find /tmp -mindepth 1 -user "$USER" -delete 2>/dev/null || true

rm -rf ~/.local/share/Trash/files/*
rm -rf ~/.local/share/Trash/info/*

echo
echo -e "${GREEN}Vacuuming system logs...${RESET}"

sudo journalctl --vacuum-time=7d

echo
echo -e "${GREEN}Removing orphan packages...${RESET}"

orphans=$(pacman -Qdtq || true)

if [[ -n "$orphans" ]]; then
  sudo pacman -Rns $orphans
else
  echo "No orphan packages."
fi

echo
echo -e "${GREEN}Refreshing package databases...${RESET}"

yay -Syy >/dev/null

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
