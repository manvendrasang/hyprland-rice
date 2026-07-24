#!/usr/bin/env bash

spinner() {

  local pid=$1
  local delay=0.08
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

  ([[ -n "${TERM:-}" ]] && [[ -t 1 ]] && ([[ -n "${TERM:-}" ]] && [[ -t 1 ]] && tput civis) || true) || true

  while kill -0 "$pid" 2>/dev/null; do

    for ((i = 0; i < ${#spin}; i++)); do

      printf "\r%c " "${spin:$i:1}"
      sleep "$delay"

    done

  done

  printf "\r"

  ([[ -n "${TERM:-}" ]] && [[ -t 1 ]] && ([[ -n "${TERM:-}" ]] && [[ -t 1 ]] && tput cnorm) || true) || true
}
