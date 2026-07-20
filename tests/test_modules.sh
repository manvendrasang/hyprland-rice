#!/usr/bin/env bash

source tests/common.sh

discover_modules

[[ ${#AVAILABLE_MODULES[@]} -gt 0 ]]

assert_true module_exists desktop

assert_false module_exists fake_module

load_module desktop

assert_equals Desktop "$NAME"