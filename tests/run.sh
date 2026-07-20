#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASSED=0
FAILED=0

echo
echo "==========================================="
echo "        HyprX Test Suite"
echo "==========================================="
echo

run_suite() {

    local directory="$1"

    for test in "$directory"/*.sh; do

        [[ -f "$test" ]] || continue

        printf "%-45s" "$(basename "$test")"

        if bash "$test" >/dev/null; then
            echo "[PASS]"
            ((PASSED++))
        else
            echo "[FAIL]"
            ((FAILED++))
        fi

    done

}

run_suite "$ROOT_DIR/tests"
run_suite "$ROOT_DIR/tests/integration"

echo
echo "==========================================="
echo "Passed : $PASSED"
echo "Failed : $FAILED"
echo "==========================================="

((FAILED == 0))