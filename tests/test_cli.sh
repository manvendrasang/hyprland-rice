#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CLI="$ROOT_DIR/bin/hyprx"

echo "Testing CLI..."

"$CLI" >/dev/null

# hyprx doctor now exits non-zero when it finds real issues (0 = all
# clear, 1 = warnings only, 2 = errors present) - that's intentional,
# not a bug, so this checks the exit code is one of those three
# instead of requiring doctor to always be silent/clean.
doctor_exit=0
"$CLI" doctor >/dev/null || doctor_exit=$?
if (( doctor_exit != 0 && doctor_exit != 1 && doctor_exit != 2 )); then
    echo "hyprx doctor exited with unexpected code $doctor_exit (expected 0, 1, or 2)"
    exit 1
fi

"$CLI" clean >/dev/null

"$CLI" rollback list >/dev/null

echo "CLI OK."
