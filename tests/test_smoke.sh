#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

discover_modules
discover_profiles

validate_profile developer

load_profile developer

print_module desktop >/dev/null

echo "Smoke test passed."