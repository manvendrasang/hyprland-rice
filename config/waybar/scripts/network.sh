#!/usr/bin/env bash

iface=$(ip route | awk '/default/ {print $5; exit}')

[[ -n "$iface" ]] || exit 0

stats_dir="/sys/class/net/$iface/statistics"

[[ -d "$stats_dir" ]] || exit 0

read -r rx1 < "$stats_dir/rx_bytes"
read -r tx1 < "$stats_dir/tx_bytes"

sleep 1

read -r rx2 < "$stats_dir/rx_bytes"
read -r tx2 < "$stats_dir/tx_bytes"

down=$(((rx2 - rx1) / 1024))
up=$(((tx2 - tx1) / 1024))

printf '{"text":"󰖩 %dK ↓ %dK ↑"}\n' "$down" "$up"