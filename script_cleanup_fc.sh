#!/bin/bash
# Script to clean up dead FC paths and rescan for new/free LUNs

echo "==> Flushing dead multipath paths..."
multipath -F
multipath -f

echo "==> Rescanning Fibre Channel Host Bus Adapters..."
for hba in /sys/class/fc_host/host*; do
    echo "1" > "$hba/issue_lip"
done
sleep 5
echo "==> Scanning SCSI buses for new/free LUNs..."
for scsi_host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$scsi_host/scan"
done
sleep 5
echo "==> Rebuilding multipath topology..."
multipath -v2
echo "==> Done. Current paths:"
multipath -ll
