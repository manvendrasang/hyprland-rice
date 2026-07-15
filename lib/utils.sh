#!/usr/bin/env bash

# ----------------------------------
# Generic Helpers
# ----------------------------------

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [[ $EUID -eq 0 ]]
}

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# ----------------------------------
# Files
# ----------------------------------

file_exists() {
  [[ -f "$1" ]]
}

dir_exists() {
  [[ -d "$1" ]]
}

create_dir() {
  mkdir -p "$1"
}

# ----------------------------------
# Size
# ----------------------------------

bytes_to_human() {

  local bytes=$1

  if ((bytes >= 1073741824)); then
    awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"
  elif ((bytes >= 1048576)); then
    awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"
  elif ((bytes >= 1024)); then
    awk "BEGIN {printf \"%.2f KB\", $bytes/1024}"
  else
    echo "${bytes} B"
  fi
}

# ----------------------------------
# Progress
# ----------------------------------

spinner() {

  local pid=$1

  local spin='-\|/'

  while kill -0 "$pid" 2>/dev/null; do

    for i in {0..3}; do
      printf "\r[%c] Working..." "${spin:$i:1}"
      sleep .1
    done

  done

  printf "\r"
}

# ----------------------------------
# Confirmation
# ----------------------------------

confirm() {

  read -rp "$1 [Y/n]: " answer

  case "$answer" in
  [Nn]*) return 1 ;;
  *) return 0 ;;
  esac
}

# ----------------------------------
# Temp
# ----------------------------------

make_temp() {

  mktemp -d
}

# ----------------------------------
# Disk Usage
# ----------------------------------

directory_size() {

  du -sb "$1" 2>/dev/null | awk '{print $1}'
}
