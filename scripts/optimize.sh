#!/bin/bash
# System optimization module

optimize_system() {
    msg_inf "Step 12/14: Optimizing system..."

    # --- Kernel network parameters ---
    local sysctl_conf="/etc/sysctl.d/99-routerus.conf"
    cat > "${sysctl_conf}" << 'EOF'
# RouteRus network optimization

# BBR congestion control (significantly reduces latency and bufferbloat)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Larger TCP socket buffers for high-throughput tunnels
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# Increase maximum number of open file descriptors
fs.file-max=1000000

# IP forwarding — required for VPN/routing to work
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

    sysctl --system -q 2>/dev/null || true

    # --- File descriptor limits ---
    local limits_conf="/etc/security/limits.d/99-routerus.conf"
    cat > "${limits_conf}" << 'EOF'
# RouteRus: higher file descriptor limits
*    soft nofile 1000000
*    hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF

    msg_ok "System optimized"
    echo
}
