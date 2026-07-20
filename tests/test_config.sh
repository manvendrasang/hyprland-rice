#!/usr/bin/env bash

source tests/common.sh

assert_equals developer "$(get_config PROFILE)"

set_config PROFILE gaming

load_config

assert_equals gaming "$PROFILE"

set_config PROFILE developer