#!/bin/bash
#####################################################
# How to Use This ScriptSave the file:             
# Save the script as add_multipath.sh.
# Make it executable: Run chmod +x add_multipath.sh.
# Ensure the script is run as root                  
#####################################################

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# 1. Scan for new iSCSI LUNs
echo "Scanning iSCSI hosts for new LUNs..."
for host in /sys/class/iscsi_host/host*; do
  echo "- - -" > "${host}/scan"
done

# 2. Rescan SCSI buses to recognize the devices
echo "Scanning SCSI buses..."
for bus in /sys/class/scsi_host/host*; do
  echo "- - -" > "${bus}/scan"
done

# Wait a moment for OS detection
sleep 2

# 3. Identify the newest disk device (e.g., sdb, sdc)
NEW_DEV=$(dmesg | grep -E "sd [0-9]+:[0-9]+:[0-9]+:[0-9]+: \[sd" | tail -n 1 | awk -F'[][]' '{print $2}')

if [ -z "$NEW_DEV" ]; then
  echo "No newly added SCSI device found in dmesg."
  exit 1
fi

echo "Found newest device: /dev/${NEW_DEV}"

# 4. Get the WWID of the new device
WWID=$(/lib/udev/scsi_id --whitelisted --device=/dev/${NEW_DEV})

if [ -z "$WWID" ]; then
  echo "Failed to retrieve WWID for /dev/${NEW_DEV}."
  exit 1
fi

echo "Retrieved WWID: ${WWID}"

# 5. Define your custom alias name
# You can modify this logic to pass the alias as an argument (e.g., ALIAS=$1)
ALIAS="$(hostname)_lun_$(date +%F_%H%M%S)"
CONF_FILE="/etc/multipath.conf"

# 6. Check if WWID already exists in multipath.conf
if grep -q "$WWID" "$CONF_FILE"; then
  echo "Error: WWID ${WWID} already exists in ${CONF_FILE}."
  exit 1
fi

# 7. Backup the current configuration
cp "$CONF_FILE" "${CONF_FILE}.bak_$(date +%F_%H%M%S)"

# 8. Append the new multipath entry before the closing multiplex block if it exists,
# or simply append it to the file.
echo "Adding entry to ${CONF_FILE}..."

cat << EOF >> "$CONF_FILE"

multipaths {
    multipath {
        wwid                    ${WWID}
        alias                   ${ALIAS}
    }
}
EOF

# 9. Reload multipath configuration to apply changes
echo "Reloading multipath daemon..."
systemctl reload multipathd

echo "Success! Added ${ALIAS} (${WWID}) to multipath."
multipath -ll | grep "$ALIAS"
