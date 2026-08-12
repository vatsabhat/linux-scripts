#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to fetch complete storage and iSCSI details."
  exit 1
fi

SEPARATOR="=========================================================================================="
HEADER_FORMAT="%-25s | %-60s\n"
ROW_FORMAT="%-25s | %-60s\n"

print_section_header() {
    echo -e "\n$SEPARATOR"
    echo -e "  STORAGE COMPONENT: $1"
    echo -e "$SEPARATOR"
    printf "$HEADER_FORMAT" "Property" "Details"
    echo -e "--------------------------|--------------------------------------------------------------"
}

# ==========================================
# 1. ISCSI LUN CONNECTIONS
# ==========================================
print_section_header "ISCSI TARGETS & LUNS"

if command -v iscsiadm >/dev/null 2>&1; then
    ISCSI_SESSIONS=$(iscsiadm -m session 2>/dev/null)
    if [ -z "$ISCSI_SESSIONS" ]; then
        printf "$ROW_FORMAT" "iSCSI Status" "Service installed, but no active sessions."
    else
        # Extract active targets
        while read -r line; do
            TARGET=$(echo "$line" | awk '{print $4}')
            PORTAL=$(echo "$line" | awk '{print $3}' | cut -d, -f1)
            printf "$ROW_FORMAT" "Active Target" "$TARGET"
            printf "$ROW_FORMAT" "Portal Address" "$PORTAL"
        done <<< "$ISCSI_SESSIONS"
        
        # Map iSCSI disks to block devices
        ISCSI_DISKS=$(ls -l /dev/disk/by-path/ip-* 2>/dev/null | awk '{print $9 " -> " $11}' | sed 's|.*/||')
        if [ -n "$ISCSI_DISKS" ]; then
            printf "$ROW_FORMAT" "Mapped LUN Devices" "$(echo "$ISCSI_DISKS" | tr '\n' ' ')"
        fi
    fi
else
    printf "$ROW_FORMAT" "iSCSI Initiator" "Not installed (iscsiadm command missing)."
fi


# ==========================================
# 2. PHYSICAL DISKS & PARTITIONS
# ==========================================
print_section_header "PHYSICAL DISKS & BLOCK DEVICES"

# Gather disk names, sizes, and types (HDD/SSD/iSCSI)
while read -r dev size rota; do
    TYPE="SSD"
    if [ "$rota" -eq 1 ]; then TYPE="HDD"; fi
    # Check if it's an iSCSI device path
    if ls -l /dev/disk/by-path/ip-* 2>/dev/null | grep -q "$dev"; then
        TYPE="iSCSI LUN ($TYPE)"
    fi
    printf "$ROW_FORMAT" "Disk Device (/dev/$dev)" "Size: $size | Type: $TYPE"
done <<< "$(lsblk -d -n -o NAME,SIZE,ROTA)"


# ==========================================
# 3. LOGICAL VOLUME MANAGEMENT (LVM)
# ==========================================
print_section_header "LVM CONFIGURATION"

if command -v pvs >/dev/null 2>&1; then
    # Physical Volumes
    PV_INFO=$(pvs --noheadings -o pv_name,vg_name,pv_size --units g 2>/dev/null | awk '{print $1"("$2"):"$3}')
    printf "$ROW_FORMAT" "Physical Volumes (PV)" "${PV_INFO:-None configured}"

    # Volume Groups
    VG_INFO=$(vgs --noheadings -o vg_name,vg_size,vg_free --units g 2>/dev/null | awk '{print $1"[Total:"$2", Free:"$3"]"}')
    printf "$ROW_FORMAT" "Volume Groups (VG)" "${VG_INFO:-None configured}"

    # Logical Volumes
    LV_INFO=$(lvs --noheadings -o vg_name,lv_name,lv_size --units g 2>/dev/null | awk '{print $1"/"$2":"$3}')
    printf "$ROW_FORMAT" "Logical Volumes (LV)" "${LV_INFO:-None configured}"
else
    printf "$ROW_FORMAT" "LVM Status" "LVM tools not installed or active."
fi


# ==========================================
# 4. MOUNTED FILESYSTEMS
# ==========================================
print_section_header "ACTIVE FILESYSTEMS & MOUNT POINTS"

# Loop through major permanent filesystems (excluding tmpfs, devtmpfs, etc.)
while read -r fs type size used avail percent target; do
    printf "$ROW_FORMAT" "Mount: $target" "Type: $type | Size: $size | Used: $percent ($used)"
done <<< "$(df -h -T | grep -E '^/dev/' | awk '{print $1" "$2" "$3" "$4" "$5" "$6" "$7}')"

echo -e "$SEPARATOR\n"
