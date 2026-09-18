#!/usr/bin/env bash

count=$(cliphist list | wc -l)

printf '{"text":"󰅍 %d","tooltip":"Clipboard History\\n%d items","class":"clipboard"}\n' \
"$count" \
"$count"