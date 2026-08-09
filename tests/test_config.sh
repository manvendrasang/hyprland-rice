#!/usr/bin/env bash

source tests/common.sh

assert_equals default "$(get_config THEME)"

set_config THEME dark

load_config

assert_equals dark "$THEME"

set_config THEME default
