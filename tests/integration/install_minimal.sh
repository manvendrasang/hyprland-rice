#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

set_config PROFILE minimal

load_profile minimal

validate_profile minimal

echo "Minimal integration OK."