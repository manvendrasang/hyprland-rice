#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

set_config PROFILE custom

load_profile custom

validate_profile custom

echo "Custom integration OK."