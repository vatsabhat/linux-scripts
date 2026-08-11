#!/bin/bash

# Clear terminal screen (optional, remove if unwanted)
clear

# Print System Metadata Header
echo "=========================================================================="
echo " HOSTNAME   : $(hostname)"
echo " DATE/TIME  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "=========================================================================="
echo ""

# Print the table header
printf "%-18s %-15s %-15s %-12s\n" "IP ADDRESS" "BRIDGE NAME" "INTERFACE" "LINK STATUS"
printf "%-18s %-15s %-15s %-12s\n" "----------" "-----------" "---------" "-----------"

# Loop through all available network interfaces
for iface in $(ls /sys/class/net/); do
    # 1. Get IP Address (v4)
    ip_addr=$(ip -4 -br addr show "$iface" 2>/dev/null | awk '{print $3}' | cut -d'/' -f1)
    [ -z "$ip_addr" ] && ip_addr="-"

    # 2. Check if the interface is part of a bridge
    if [ -d "/sys/class/net/$iface/master" ]; then
        master_path=$(readlink "/sys/class/net/$iface/master")
        bridge_name=$(basename "$master_path")
    elif [ -d "/sys/class/net/$iface/bridge" ]; then
        bridge_name="[Self-Bridge]"
    else
        bridge_name="-"
    fi

    # 3. Get operational link status (UP/DOWN)
    link_status=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    [ -z "$link_status" ] && link_status="UNKNOWN"

    # Print the raw data row
    printf "%-18s %-15s %-15s %-12s\n" "$ip_addr" "$bridge_name" "$iface" "$link_status"
done | column -t
