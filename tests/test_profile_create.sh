#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing profile creation..."

# Success path
create_profile testprofile "Test Profile" "A profile for testing" desktop >/dev/null

assert_true profile_exists testprofile
assert_true test -f "$HYPRX_PROFILES/testprofile/profile.conf"
assert_true test -f "$HYPRX_PROFILES/testprofile/modules.list"
assert_true grep -q "^NAME=Test Profile$" "$HYPRX_PROFILES/testprofile/profile.conf"
assert_true grep -q "^desktop$" "$HYPRX_PROFILES/testprofile/modules.list"

# Duplicate id should be rejected
assert_false create_profile testprofile "Dup" "Dup" desktop

# Invalid module should be rejected and nothing left behind
assert_false create_profile badprofile "Bad" "Bad" not-a-real-module
assert_false profile_exists badprofile

# No modules at all should be rejected
assert_false create_profile emptyprofile "Empty" "Empty"
assert_false profile_exists emptyprofile

echo "Profile creation OK."
