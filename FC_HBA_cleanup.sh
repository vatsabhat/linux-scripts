#!/bin/bash
# RHEL FC HBA Post-Removal Cleanup Script

echo "=== Step 1: Removing Link-Down / Stale FC Hosts ==="
for host in /sys/class/fc_host/host*; do
    if [ -d "$host" ]; then
        hostname=$(basename "$host")
        port_state=$(cat "$host/port_state")
        
        if [ "$port_state" = "Linkdown" ] || [ "$port_state" = "Offline" ]; then
            echo "Removing dead FC host: $hostname (State: $port_state)"
            echo 1 > "/sys/class/scsi_host/$hostname/delete" 2>/dev/null
        fi
    fi
done

echo "=== Step 2: Purging Offline SCSI Devices ==="
for dev in /sys/block/sd*; do
    if [ -d "$dev/device" ]; then
        devname=$(basename "$dev")
        state=$(cat "$dev/device/state" 2>/dev/null)
        
        if [ "$state" = "offline" ]; then
            echo "Deleting stale SCSI device: $devname"
            echo 1 > "$dev/device/delete" 2>/dev/null
        fi
    fi
done

echo "=== Step 3: Refreshing Multipath Configuration ==="
if systemctl is-active --quiet multipathd; then
    echo "Flushing unused multipath maps..."
    multipath -F
    echo "Reloading active multipath maps..."
    multipath -r
    echo "Current Multipath Status:"
    multipath -ll | grep -E "dm-|fail|active"
else
    echo "multipathd is not running or not used."
fi

echo "=== Cleanup Complete ==="
