#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

set_config PROFILE developer

load_profile developer

validate_profile developer

echo "Developer integration OK."