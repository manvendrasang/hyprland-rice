#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

pass() {
    printf "✓ %s\n" "$1"
}

fail() {
    printf "✗ %s\n" "$1"
    exit 1
}

assert_true() {

    "$@" >/dev/null 2>&1 \
        && pass "$*" \
        || fail "$*"

}

assert_false() {

    if "$@" >/dev/null 2>&1; then
        fail "$*"
    else
        pass "$*"
    fi

}

assert_equals() {

    local expected="$1"
    local actual="$2"

    [[ "$expected" == "$actual" ]] \
        && pass "$expected" \
        || fail "Expected '$expected' got '$actual'"

}

assert_file_exists() {

    [[ -f "$1" ]] \
        && pass "$1 exists" \
        || fail "$1 missing"

}

assert_directory_exists() {

    [[ -d "$1" ]] \
        && pass "$1 exists" \
        || fail "$1 missing"

}

assert_not_empty() {

    [[ -n "$1" ]] \
        && pass "value exists" \
        || fail "value empty"

}

assert_command_success() {

    "$@" >/dev/null 2>&1 \
        && pass "$*" \
        || fail "$*"

}

assert_command_failure() {

    if "$@" >/dev/null 2>&1; then
        fail "$*"
    else
        pass "$*"
    fi

}