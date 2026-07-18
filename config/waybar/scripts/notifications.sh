#!/usr/bin/env bash

if ! command -v swaync-client >/dev/null 2>&1; then
    exit 0
fi

if swaync-client -D | grep -q true; then
    printf '{"text":"󰂛"}\n'
else
    printf '{"text":"󰂚"}\n'
fi