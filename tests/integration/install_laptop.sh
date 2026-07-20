#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

set_config PROFILE laptop

load_profile laptop

validate_profile laptop

echo "Laptop profile OK."