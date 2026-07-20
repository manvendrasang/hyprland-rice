#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASSED=0
FAILED=0

run_suite() {

    local directory="$1"

    [[ -d "$directory" ]] || return

    while IFS= read -r -d '' test; do

        printf "%-45s" "$(basename "$test")"

        if bash "$test"; then
            echo "[PASS]"
            ((PASSED++))
        else
            echo "[FAIL]"
            ((FAILED++))
        fi

    done < <(find "$directory" -maxdepth 1 -name "*.sh" -print0 | sort -z)

}

echo
echo "========================================="
echo "        HyprX Test Suite"
echo "========================================="
echo

run_suite "$ROOT_DIR/tests"

run_suite "$ROOT_DIR/tests/integration"

echo
echo "========================================="
echo "Passed : $PASSED"
echo "Failed : $FAILED"
echo "========================================="

((FAILED == 0))