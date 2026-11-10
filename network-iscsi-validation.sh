
#!/bin/bash

echo "======================================"
echo " RHEL 10 iSCSI / NIC / MULTIPATH CHECK"
echo "======================================"

echo
echo "1. OS AND KERNEL"
cat /etc/redhat-release
uname -r

echo
echo "2. BROADCOM DRIVER"
modinfo -F version bnxt_en

echo
echo "3. NIC INTERFACES"
for nic in ens1f0np0 ens1f1np1; do
    if ip link show "$nic" >/dev/null 2>&1; then
        echo "---- $nic ----"
        ethtool "$nic" | grep -E 'Speed:|Duplex:|Link detected:'
        ethtool -i "$nic" | grep -E 'driver:|version:|firmware-version:'
    fi
done

echo
echo "4. ISCSI SERVICE"
systemctl is-active iscsid
iscsiadm -m session

echo
echo "5. MULTIPATH SERVICE"
systemctl is-active multipathd
multipath -ll
multipathd show paths

echo
echo "6. STORAGE DEVICES"
lsblk

echo
echo "7. RECENT HARDWARE ERRORS"
journalctl -k --since "30 minutes ago" |
grep -Ei 'bnxt|IOMMU|IO_PAGE_FAULT|firmware reset|NOP_TIMEDOUT|I/O error' |
tail -50

echo
echo "======================================"
echo " VALIDATION COMPLETED"
echo "======================================"
