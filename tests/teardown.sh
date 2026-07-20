#!/usr/bin/env bash

set -euo pipefail

[[ -n "${TEST_ROOT:-}" ]] && rm -rf "$TEST_ROOT"