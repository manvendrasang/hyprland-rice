#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

resolve_packages

[[ ${#PACKAGE_QUEUE[@]} -gt 0 ]]

[[ -f "$ROOT_DIR/services.list" ]]

echo "Smoke test passed."
