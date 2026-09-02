#!/usr/bin/env bash
#
# tune-k8s-worker.sh
# Automates RHEL 10 performance tuning specifically for dedicated Kubernetes Worker Nodes.
# Must be executed with root/sudo privileges.

set -euo pipefail

# Ensure script runs as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo or as root." >&2
  exit 1
fi

echo "========================================================="
echo " Starting Dedicated Kubernetes Worker Node Tuning (RHEL 10)"
echo "========================================================="

# ---------------------------------------------------------
# 1. Disable Swap (Kubernetes Prerequisite)
# ---------------------------------------------------------
echo "[-] Disabling swap to protect worker latency predictability..."
swapoff -a
sed -i.bak '/swap/d' /etc/fstab
echo "[✓] Swap permanently disabled."

# ---------------------------------------------------------
# 2. Kernel & OS Performance Parameters (Worker Density Scaled)
# ---------------------------------------------------------
echo "[-] Applying kernel and Virtual Memory optimizations..."
cat << 'EOF' > /etc/sysctl.d/99-kubernetes-performance.conf
# Maximum number of open files (vital for massive pod densities)
fs.file-max = 2097152

# Increase max user watches for container log tracking and events
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# Virtual Memory performance adjustments
vm.overcommit_memory = 1
vm.max_map_count = 262144
vm.swappiness = 0

# Adjust dirty page flushing to maintain consistent worker node disk writes
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF

# ---------------------------------------------------------
# 3. High-Performance Network Tuning (Pod-to-Pod Routing)
# ---------------------------------------------------------
echo "[-] Optimizing network stack for high-density pod routing..."
cat << 'EOF' > /etc/sysctl.d/98-kubernetes-network.conf
# Max network packet backlog queue (handles bursty pod traffic)
net.core.netdev_max_backlog = 100000

# Increase maximum number of open listening sockets for containers
net.core.somaxconn = 32768

# Tune TCP buffer sizes (Min, Default, Max in bytes) for high bandwidth pods
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Enable fast connection recycle properties for fast-cycling workloads
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Increase local port ranges to prevent exhaustion from massive pod-to-pod mesh traffic
net.ipv4.ip_local_port_range = 1024 65535

# Ensure max tracking table capacity for high-density pod connections
net.netfilter.nf_conntrack_max = 1048576
EOF

# Reload parameters immediately
sysctl --system
echo "[✓] Sysctl configuration complete."

# ---------------------------------------------------------
# 4. TuneD Dynamic Tuning Setup
# ---------------------------------------------------------
echo "[-] Configuring TuneD service..."
dnf install -y tuned
systemctl enable --now tuned

# Use "network-latency" or "throughput-performance" depending on focus. 
# Throughput-performance is optimal for general massive pod multi-tenancy.
tuned-adm profile throughput-performance
echo "[✓] TuneD set to throughput-performance profile."

# ---------------------------------------------------------
# 5. Pod Limit & Security Boundary Tuning
# ---------------------------------------------------------
echo "[-] Increasing process and thread security boundaries for workers..."
cat << 'EOF' > /etc/security/limits.d/99-kubernetes-worker.conf
# Ensure pods do not fail due to host-level process/thread bounds
*          soft    nproc     65535
*          hard    nproc     65535
*          soft    nofile    1048576
*          hard    nofile    1048576
EOF
echo "[✓] User limits updated."

# ---------------------------------------------------------
# 6. Disk I/O Block Optimization (Ephemeral Data/NVMe)
# ---------------------------------------------------------
echo "[-] Optimizing block layer I/O schedulers..."
# Loop through non-rotational disks (SSDs/NVMes) and set scheduler to none
for dev in /sys/block/*; do
  if [ -f "$dev/queue/rotational" ] && [ "$(cat "$dev/queue/rotational")" -eq 0 ]; then
    DISK_NAME=$(basename "$dev")
    if [ -f "$dev/queue/scheduler" ]; then
      echo "none" > "$dev/queue/scheduler" 2>/dev/null || true
      echo "    -> Set scheduler to 'none' for NVMe/SSD: $DISK_NAME"
    fi
  fi
done
echo "[✓] Disk scheduling optimized."

# ---------------------------------------------------------
# 7. Install Troubleshooting and Diagnostics Stack
# ---------------------------------------------------------
echo "[-] Installing worker node disk I/O, network, and system debugging tools..."
dnf install -y sysstat iotop bcc-tools ethtool iproute tcptraceroute conntrack-tools

echo "[✓] Diagnostics utilities successfully installed."

echo "========================================================="
echo " Worker Node Optimization Completed Successfully!"
echo "========================================================="
