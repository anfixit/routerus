#!/bin/bash
# System update module

update_system() {
    msg_inf "Step 1/14: Updating system packages..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get dist-upgrade -y -qq
    apt-get autoremove -y -qq
    apt-get autoclean -y -qq

    msg_ok "System updated successfully"
    echo
}
