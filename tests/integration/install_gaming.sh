#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

set_config PROFILE gaming

load_profile gaming

validate_profile gaming

echo "Gaming integration OK."