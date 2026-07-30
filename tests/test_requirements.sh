#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing package requirements..."

# steam is a known entry with a multilib hint
HINT="$(get_requirement_hint steam)"
assert_not_empty "$HINT"
assert_true grep -q "multilib" <<< "$HINT"

# an unknown package should return empty, not error
UNKNOWN_HINT="$(get_requirement_hint totally-not-a-real-package)"
assert_equals "" "$UNKNOWN_HINT"

echo "Requirements database OK."
