#!/bin/bash
# ------------------------------------------------------------------
# Script to completely remove and delete all iSCSI paths and nodes
# ------------------------------------------------------------------

echo "Step 1: Logging out of all active iSCSI sessions..."
iscsiadm -m node --logoutall=all

echo "Step 2: Deleting all discovered iSCSI targets from the database..."
iscsiadm -m node -o delete

echo "Step 3: Triggering a SCSI bus rescan to clear ghost multipath/block devices..."
if [ -d /sys/class/scsi_host ]; then
    for host in /sys/class/scsi_host/host*; do
        echo "- Rescanning $(basename "$host")..."
        echo "- - -" > "$host/scan"
    done
fi

echo "Step 4: Cleaning up any stale device-mapper entries..."
multipath -F

echo "iSCSI path deletion complete. You can now safely attempt to start multipathd."
