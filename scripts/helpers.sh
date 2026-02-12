#!/bin/bash
# Helper functions for RouteRus installation

set -euo pipefail

# --- Output formatting ---

msg_ok() {
    echo -e "\e[1;42m $1 \e[0m"
}

msg_err() {
    echo -e "\e[1;41m $1 \e[0m"
}

msg_inf() {
    echo -e "\e[1;34m$1\e[0m"
}

msg_warn() {
    echo -e "\e[1;43m $1 \e[0m"
}

# --- Random generation ---

gen_random_string() {
    local length="${1:-10}"
    head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "${length}"
    echo
}

get_random_port() {
    echo $(( ((RANDOM << 15) | RANDOM) % 49152 + 10000 ))
}

check_port_free() {
    local port="$1"
    ! nc -z 127.0.0.1 "${port}" &>/dev/null
}

make_free_port() {
    local port
    while true; do
        port="$(get_random_port)"
        if check_port_free "${port}"; then
            echo "${port}"
            return
        fi
    done
}

# --- System helpers ---

command_exists() {
    command -v "$1" &>/dev/null
}

wait_for_service() {
    local service="$1"
    local max_wait="${2:-30}"
    local count=0

    while ! systemctl is-active --quiet "${service}" && [[ ${count} -lt ${max_wait} ]]; do
        sleep 1
        ((count++))
    done

    systemctl is-active --quiet "${service}"
}

backup_file() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        cp "${file}" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        msg_inf "Backed up: ${file}"
    fi
}
