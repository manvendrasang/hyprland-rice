#!/usr/bin/env bash

iface=$(ip route | awk '/default/ {print $5; exit}')

rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes)
tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes)

sleep 1

rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes)
tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes)

down=$(((rx2-rx1)/1024))
up=$(((tx2-tx1)/1024))

printf '{"text":"󰖩 %dK ↓ %dK ↑"}\n' "$down" "$up"