#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing installer pipeline..."

# Bootstrap
[[ "${HYPRX_INITIALIZED:-false}" == "true" ]]

# Profiles
discover_profiles
[[ ${#AVAILABLE_PROFILES[@]} -gt 0 ]]

# Modules
discover_modules
[[ ${#AVAILABLE_MODULES[@]} -gt 0 ]]

# Validate default profile
validate_profile developer

# Load profile
load_profile developer

[[ "${CURRENT_PROFILE}" == "developer" ]]
[[ ${#SELECTED_MODULES[@]} -gt 0 ]]

# Every module in the profile should exist and load
for module in "${SELECTED_MODULES[@]}"; do

    module_exists "$module"

    load_module "$module"

done

echo "Installer pipeline OK."