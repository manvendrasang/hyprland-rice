#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing report generation..."

FAILED_PACKAGES=()

INSTALLED_PACKAGES=()

SKIPPED_PACKAGES=()

REPORT_FILE="/tmp/hyprx-test-report.txt"

generate_report >/dev/null

echo "Report generation OK."