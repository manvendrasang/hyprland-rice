#!/usr/bin/env bash

official=0
aur=0

if command -v checkupdates >/dev/null 2>&1; then
    official=$(checkupdates 2>/dev/null | wc -l)
fi

if command -v yay >/dev/null 2>&1; then
    aur=$(yay -Qua 2>/dev/null | wc -l)
elif command -v paru >/dev/null 2>&1; then
    aur=$(paru -Qua 2>/dev/null | wc -l)
fi

total=$((official + aur))

if (( total == 0 )); then
    class="ok"
elif (( total < 10 )); then
    class="warn"
else
    class="critical"
fi

printf '{"text":"󰏖 %d","tooltip":"Official: %d\\nAUR: %d","class":"%s"}\n' \
    "$total" \
    "$official" \
    "$aur" \
    "$class"