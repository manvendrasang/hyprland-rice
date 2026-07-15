#!/bin/bash

if swaync-client -D | grep -q true
then
    echo '{"text":"󰂛"}'
else
    echo '{"text":"󰂚"}'
fi