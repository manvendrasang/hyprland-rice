#!/usr/bin/env bash

source tests/common.sh

discover_profiles

[[ ${#AVAILABLE_PROFILES[@]} -gt 0 ]]

validate_profile developer

load_profile developer

[[ ${#SELECTED_MODULES[@]} -gt 0 ]]