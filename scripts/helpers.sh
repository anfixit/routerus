#!/bin/bash
# Helper functions for RouteRus installation

# Colors and formatting
msg_ok() { echo -e "\e[1;42m $1 \e[0m"; }
msg_err() { echo -e "\e[1;41m $1 \e[0m"; }
msg_inf() { echo -e "\e[1;34m$1\e[0m"; }
msg_warn() { echo -e "\e[1;43m $1 \e[0m"; }

# Generate random string
gen_random_string() {
    local length="${1:-10}"
    head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
    echo
}

# Generate random port
get_port() {
    echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
}

# Check if port is free
check_port_free() {
    local port=$1
    ! nc -z 127.0.0.1 $port &>/dev/null
}

# Make random free port
make_port() {
    while true; do
        PORT=$(get_port)
        if check_port_free $PORT; then 
            echo $PORT
            break
        fi
    done
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Wait for service to be ready
wait_for_service() {
    local service=$1
    local max_wait=${2:-30}
    local count=0
    
    while ! systemctl is-active --quiet "$service" && [ $count -lt $max_wait ]; do
        sleep 1
        ((count++))
    done
    
    systemctl is-active --quiet "$service"
}

# Backup file
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        msg_inf "✓ Backed up: $file"
    fi
}

# Export all functions
export -f msg_ok msg_err msg_inf msg_warn
export -f gen_random_string get_port check_port_free make_port
export -f command_exists wait_for_service backup_file
