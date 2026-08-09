#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Isolate tests from the real repo state (config/hyprx.conf) so
# running the suite never mutates tracked files on disk.
source "$ROOT_DIR/tests/setup.sh" >/dev/null
trap 'source "$ROOT_DIR/tests/teardown.sh"' EXIT

PASSED=0
FAILED=0

run_suite() {

    local directory="$1"
    local pattern="$2"

    [[ -d "$directory" ]] || return

    while IFS= read -r -d '' test; do

        printf "%-45s" "$(basename "$test")"

        if bash "$test"; then
            echo "[PASS]"
            PASSED=$((PASSED + 1))
        else
            echo "[FAIL]"
            FAILED=$((FAILED + 1))
        fi

    done < <(find "$directory" -maxdepth 1 -name "$pattern" -print0 | sort -z)

}

echo
echo "========================================="
echo "        HyprX Test Suite"
echo "========================================="
echo

run_suite "$ROOT_DIR/tests" "test_*.sh"

echo
echo "========================================="
echo "Passed : $PASSED"
echo "Failed : $FAILED"
echo "========================================="

((FAILED == 0))