#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing retry..."

retry 1 true

echo "Retry OK."