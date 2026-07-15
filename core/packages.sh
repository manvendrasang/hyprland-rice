#!/usr/bin/env bash

pkg_exists() {
  command -v "$1" >/dev/null 2>&1
}
