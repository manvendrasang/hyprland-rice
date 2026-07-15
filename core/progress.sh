#!/usr/bin/env bash

progress() {

    local current=$1
    local total=$2
    local width=40

    ((total==0)) && total=1

    local percent=$(( current * 100 / total ))
    local filled=$(( width * current / total ))

    printf "\r["

    for ((i=0;i<filled;i++)); do
        printf "█"
    done

    for ((i=filled;i<width;i++)); do
        printf " "
    done

    printf "] %3d%%" "$percent"

}