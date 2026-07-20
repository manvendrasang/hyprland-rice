#!/usr/bin/env bash

source tests/common.sh

assert_equals true "$HYPRX_INITIALIZED"

assert_true test -d "$HYPRX_MODULES"

assert_true test -d "$HYPRX_PROFILES"

assert_true test -d "$HYPRX_CONFIG"

assert_true test -d "$HYPRX_COMMANDS"