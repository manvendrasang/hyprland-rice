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

    if "$@" >/dev/null 2>&1; then
        pass "$*"
    else
        fail "$*"
    fi

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

    if [[ "$expected" == "$actual" ]]; then
        pass "$expected"
    else
        fail "Expected '$expected' got '$actual'"
    fi

}

assert_file_exists() {

    if [[ -f "$1" ]]; then
        pass "$1 exists"
    else
        fail "$1 missing"
    fi

}

assert_directory_exists() {

    if [[ -d "$1" ]]; then
        pass "$1 exists"
    else
        fail "$1 missing"
    fi

}

assert_not_empty() {

    if [[ -n "$1" ]]; then
        pass "value exists"
    else
        fail "value empty"
    fi

}

assert_command_success() {

    if "$@" >/dev/null 2>&1; then
        pass "$*"
    else
        fail "$*"
    fi

}

assert_command_failure() {

    if "$@" >/dev/null 2>&1; then
        fail "$*"
    else
        pass "$*"
    fi

}