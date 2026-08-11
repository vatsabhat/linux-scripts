Here is a complete, automated bash script to execute the migration.
## ⚠️ Critical Prerequisites Before Running

   1. Identify Disks: Run lsblk and ensure /dev/sda is your old FC disk and /dev/sdb is your new iSCSI LUN. Update the variables at the top of the script if they differ.
   2. Backup: Ensure you have a valid backup or snapshot of the VM before proceeding.
   3. Run as Root: This script must be executed with root privileges (sudo). [1] 

#!/bin/bash
# ==============================================================================# RHEL 8 VM MIGRATION SCRIPT: FC LUN TO iSCSI BOOT LUN (WITH LVM MIRRORING)# ==============================================================================
# --- Configuration Variables ---
OLD_FC_DISK="/dev/sda"
OLD_FC_LVM_PART="${OLD_FC_DISK}3" # Update if your LVM partition index is different

NEW_ISCSI_DISK="/dev/sdb"
NEW_EFI_PART="${NEW_ISCSI_DISK}1"
NEW_BOOT_PART="${NEW_ISCSI_DISK}2"
NEW_LVM_PART="${NEW_ISCSI_DISK}3"

VG_NAME="root_vg"
LV_NAME="root_lv"
# --- Helper Functions ---
log_info() {
    echo -e "\n\e[1;34m[INFO]\e[0m $1"
}

log_success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $1"
}

log_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
    exit 1
}
# --- Root Check ---if [ "$EUID" -ne 0 ]; then
   log_error "This script must be run as root or with sudo."fi
# ==============================================================================# PHASE 1: Partition the iSCSI LUN# ==============================================================================
log_info "Phase 1: Partitioning the new iSCSI disk (${NEW_ISCSI_DISK})..."
if [ ! -b "$NEW_ISCSI_DISK" ]; then
    log_error "Target iSCSI disk ${NEW_ISCSI_DISK} not found!"fi
# Create GPT partition layout matching RHEL 8 boot specifications
parted "${NEW_ISCSI_DISK}" mklabel gpt || log_error "Failed to create GPT label."
parted "${NEW_ISCSI_DISK}" mkpart "EFI" fat32 1MiB 600MiB || log_error "Failed to create EFI partition."
parted "${NEW_ISCSI_DISK}" set 1 esp on
parted "${NEW_ISCSI_DISK}" mkpart "boot" xfs 600MiB 1600MiB || log_error "Failed to create Boot partition."
parted "${NEW_ISCSI_DISK}" mkpart "lvm" 1600MiB 100% || log_error "Failed to create LVM partition."
parted "${NEW_ISCSI_DISK}" set 3 lvm on
# Wait for system to refresh device nodes
udevadm settle
log_success "Partitioning complete."
# ==============================================================================# PHASE 2: Mirror and Sync Non-LVM Boot Filesystems# ==============================================================================
log_info "Phase 2: Formatting and syncing non-LVM boot file systems..."

mkfs.vfat -F 32 "${NEW_EFI_PART}" || log_error "Failed to format EFI partition."
mkfs.xfs -f "${NEW_BOOT_PART}" || log_error "Failed to format Boot partition."
# Temporary mount points for data sync
mkdir -p /mnt/new_efi /mnt/new_boot
mount "${NEW_EFI_PART}" /mnt/new_efi || log_error "Failed to mount new EFI partition."
mount "${NEW_BOOT_PART}" /mnt/new_boot || log_error "Failed to mount new Boot partition."

log_info "Syncing data to new /boot and /boot/efi partitions..."
rsync -avHAX /boot/efi/ /mnt/new_efi/ || log_error "Failed to sync EFI files."
rsync -avHAX /boot/ /mnt/new_boot/ --exclude=efi/ || log_error "Failed to sync Boot files."

umount /mnt/new_efi
umount /mnt/new_boot
log_success "Boot synchronization complete."
# ==============================================================================# PHASE 3: Migrate LVM Mirroring to iSCSI# ==============================================================================
log_info "Phase 3: Setting up LVM mirror and migrating data..."

pvcreate "${NEW_LVM_PART}" || log_error "Failed to create physical volume on ${NEW_LVM_PART}."
vgextend "${VG_NAME}" "${NEW_LVM_PART}" || log_error "Failed to extend ${VG_NAME}."

log_info "Converting ${LV_NAME} to an LVM mirror. This will take time..."
lvconvert -m 1 "/dev/${VG_NAME}/${LV_NAME}" "${NEW_LVM_PART}" || log_error "Failed to initialize LVM mirror."
# Polling loop to wait for mirror synchronization to hit 100%
log_info "Waiting for LVM mirror synchronization to reach 100%..."while true; do
    SYNC_PERCENT=$(lvs -o lv_attr,copy_percent --noheadings "/dev/${VG_NAME}/${LV_NAME}" | awk '{print $2}')
    if [ -z "$SYNC_PERCENT" ] || [ "$SYNC_PERCENT" == "100.00" ]; then
        break
    fi
    echo -ne "Sync Progress: ${SYNC_PERCENT}%\r"
    sleep 5done
echo ""
log_success "LVM mirror is fully synchronized."

log_info "Splitting mirror and removing old FC PV..."
lvconvert -m 0 "/dev/${VG_NAME}/${LV_NAME}" "${OLD_FC_LVM_PART}" || log_error "Failed to split mirror."
vgreduce "${VG_NAME}" "${OLD_FC_LVM_PART}" || log_error "Failed to reduce VG."
pvremove "${OLD_FC_LVM_PART}" || log_error "Failed to remove old PV."
log_success "LVM migration complete."
# ==============================================================================# PHASE 4: Rebuild initramfs with iSCSI Drivers# ==============================================================================
log_info "Phase 4: Rebuilding initramfs with iSCSI and network drivers for RHEL 8..."
dracut --force --add "network iscsi lvm" --kver "$(uname -r)" || log_error "Dracut failed to rebuild initramfs."
log_success "initramfs successfully updated."
# ==============================================================================# PHASE 5: Update fstab and Reinstall GRUB2# ==============================================================================
log_info "Phase 5: Updating /etc/fstab and reinstalling GRUB2..."

NEW_EFI_UUID=$(blkid -o value -s UUID "${NEW_EFI_PART}")
NEW_BOOT_UUID=$(blkid -o value -s UUID "${NEW_BOOT_PART}")
if [ -z "$NEW_EFI_UUID" ] || [ -z "$NEW_BOOT_UUID" ]; then
    log_error "Could not fetch new partition UUIDs."fi
# Backup current fstab
cp /etc/fstab /etc/fstab.bak
# Capture old UUIDs for cleanup
OLD_EFI_UUID=$(awk '/\/boot\/efi/ {print $1}' /etc/fstab | sed 's/UUID=//')
OLD_BOOT_UUID=$(awk '/\/boot/ && !/\/boot\/efi/ {print $1}' /etc/fstab | sed 's/UUID=//')
# Replace UUIDs in /etc/fstab
sed -i "s/$OLD_EFI_UUID/$NEW_EFI_UUID/g" /etc/fstab
sed -i "s/$OLD_BOOT_UUID/$NEW_BOOT_UUID/g" /etc/fstab
# Mount new partitions to current runtime system to regenerate GRUB properly
mount "${NEW_BOOT_PART}" /boot
mount "${NEW_EFI_PART}" /boot/efi

log_info "Generating new GRUB configuration..."
grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg || log_error "Failed to update GRUB config."
log_success "GRUB updated."
# ==============================================================================# PHASE 6: Post-Flight Validation Instructions# ==============================================================================
echo -e "\n=========================================================================="
echo -e "\e[1;32mMIGRATION SCRIPT EXECUTION COMPLETE\e[0m"
echo -e "=========================================================================="
echo -e "1. Shut down the virtual machine: \e[1;33msudo poweroff\e[0m"
echo -e "2. In your KVM Hypervisor (virt-manager / virsh):"
echo -e "   - Detach the old Fibre Channel LUN storage disk."
echo -e "   - Verify the iSCSI LUN is attached and marked as the primary boot device."
echo -e "3. Power on the VM and verify the root mount utilizing \e[1;33mlsblk\e[0m."
echo -e "==========================================================================\n"

## How to use this script:

   1. Save the contents above to a file named migrate.sh inside your VM.
   2. Make it executable: chmod +x migrate.sh
   3. Execute it: sudo ./migrate.sh [2] 

