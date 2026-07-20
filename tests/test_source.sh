#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for i in {1..25}; do
    bash -c "
        source \"$ROOT_DIR/lib/bootstrap.sh\"
    "
done

echo "Bootstrap sourcing OK."