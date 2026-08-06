#!/bin/bash
# ==============================================================================
# Enterprise Linux Health Check & Inventory
# Compatible: RHEL 7/8/9
# Version: 1.0 (condensed edition)
# ==============================================================================

REPORT="Linux_Server_Report_$(hostname)_$(date +%F_%H%M%S).txt"
LINE="================================================================================"

section(){ echo; echo "$LINE"; echo "$1"; echo "$LINE"; }

exec > >(tee "$REPORT")

section "SERVER INFORMATION"
echo "Hostname        : $(hostname)"
echo "FQDN            : $(hostname -f 2>/dev/null)"
echo "OS              : $(cat /etc/redhat-release 2>/dev/null)"
echo "Kernel          : $(uname -r)"
echo "Architecture    : $(uname -m)"
echo "Uptime          : $(uptime -p)"
echo "CPU             : $(lscpu | awk -F: "/Model name/{print \$2}" | xargs)"
echo "CPUs            : $(nproc)"
echo "Memory          : $(free -h | awk "/Mem/{print \$2}")"

section "NETWORK"
printf "%-12s %-8s %-18s %-6s %-8s\n" Interface State IPv4 MTU Speed
for i in $(ls /sys/class/net|grep -v lo); do
 ip=$(ip -4 -o addr show "$i"|awk '{print $4}')
 st=$(cat /sys/class/net/$i/operstate)
 mtu=$(cat /sys/class/net/$i/mtu)
 sp=$(cat /sys/class/net/$i/speed 2>/dev/null); [ -z "$sp" ] && sp="-"
 printf "%-12s %-8s %-18s %-6s %-8s\n" "$i" "$st" "${ip:--}" "$mtu" "$sp"
done
echo; ip route
echo; cat /etc/resolv.conf

section "FILESYSTEM"
df -hT

section "LVM"
pvs 2>/dev/null
vgs 2>/dev/null
lvs -a 2>/dev/null

section "BLOCK DEVICES"
lsblk -f

section "UUID"
blkid

section "ISCSI"
systemctl is-active iscsid 2>/dev/null
iscsiadm -m session 2>/dev/null || true
iscsiadm -m node 2>/dev/null || true

section "MULTIPATH"
systemctl is-active multipathd 2>/dev/null
multipath -ll 2>/dev/null || echo "multipath not configured"

section "LVM -> PV -> Multipath -> WWID -> Mount"
printf "%-15s %-12s %-20s %-20s %-36s\n" LV VG PV MOUNT WWID
lvs --noheadings --separator='|' -o lv_name,vg_name 2>/dev/null | while IFS='|' read -r lv vg; do
 lv=$(xargs<<<"$lv"); vg=$(xargs<<<"$vg")
 lvpath="/dev/$vg/$lv"
 mnt=$(findmnt -nr -S "$lvpath" -o TARGET)
 pv=$(pvs --noheadings -S vg_name="$vg" -o pv_name|head -1|xargs)
 alias=$(basename "$pv")
 wwid=$(multipath -ll 2>/dev/null|awk -v a="$alias" '$1==a{getline;print $1}')
 printf "%-15s %-12s %-20s %-20s %-36s\n" "$lv" "$vg" "$pv" "${mnt:--}" "${wwid:--}"
done

section "SERVICES"
echo "-- Running --"
systemctl list-units --type=service --state=running --no-pager
echo "-- Failed --"
systemctl --failed --no-pager
echo "-- Enabled --"
systemctl list-unit-files --type=service --state=enabled --no-pager

section "SYSTEM HEALTH"
free -h
swapon --show
uptime
echo
echo "Top CPU"
ps -eo pid,comm,%cpu --sort=-%cpu|head
echo
echo "Top Memory"
ps -eo pid,comm,%mem --sort=-%mem|head

section "EXECUTIVE HEALTH SUMMARY"
critical=0; warning=0; info=0

fp=$(multipath -ll 2>/dev/null|egrep -ci 'failed|faulty')
if [ "$fp" -gt 0 ]; then
 echo "[CRITICAL] Failed/Faulty multipath paths: $fp"
 critical=$((critical+1))
else
 echo "[PASS] Multipath healthy"
 info=$((info+1))
fi

df -P|awk 'NR>1{gsub("%","",$5); if($5>=90) print $6,$5}'|while read fs u;do
 echo "[WARNING] Filesystem $fs usage ${u}%"
done
wcnt=$(df -P|awk 'NR>1{gsub("%","",$5); if($5>=90)c++}END{print c+0}')
warning=$((warning+wcnt))

for s in multipathd iscsid; do
 if systemctl is-active $s >/dev/null 2>&1; then
   echo "[PASS] $s running"; info=$((info+1))
 else
   echo "[CRITICAL] $s not running"; critical=$((critical+1))
 fi
done

echo
if [ $critical -gt 0 ]; then overall=CRITICAL
elif [ $warning -gt 0 ]; then overall=WARNING
else overall=HEALTHY; fi

echo "Overall Health : $overall"
echo "Critical       : $critical"
echo "Warnings       : $warning"
echo "Info           : $info"

echo
echo "Recommended Remediation:"
[ $critical -gt 0 ] && echo "- Restore storage/services before production workload."
[ $warning -gt 0 ] && echo "- Review filesystem utilization and network/service warnings."
echo "- Verify backups, monitoring, and OS patch levels."
echo
echo "Report saved to: $REPORT"
