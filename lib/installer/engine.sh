#!/usr/bin/env bash

source "$ROOT_DIR/lib/installer/preflight.sh"

run_install_engine() {

    preflight || {

        error

        echo

        echo "Preflight failed."

        exit 1

    }

    success "Ready."

}