#!/usr/bin/env bash

official=$(checkupdates 2>/dev/null | wc -l)
aur=$(yay -Qua 2>/dev/null | wc -l)

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