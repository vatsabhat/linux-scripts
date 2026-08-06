#!/bin/bash
###############################################################################
# Linux Server Inventory & Health Report
# Compatible : RHEL 7 / 8 / 9
###############################################################################

REPORT="Linux_Server_Report_$(hostname)_$(date +%F_%H%M).txt"

exec >"$REPORT"

LINE="================================================================================"

section()
{
echo
echo "$LINE"
echo "$1"
echo "$LINE"
}

###############################################################################
section "SERVER INFORMATION"

echo "Hostname          : $(hostname)"
echo "FQDN              : $(hostname -f 2>/dev/null)"
echo "Date              : $(date)"
echo "OS                : $(cat /etc/redhat-release 2>/dev/null)"
echo "Kernel            : $(uname -r)"
echo "Architecture      : $(uname -m)"
echo "Uptime            : $(uptime -p)"
echo "CPU Model         : $(lscpu | awk -F: '/Model name/{print $2}' | xargs)"
echo "CPU(s)            : $(nproc)"
echo "Memory            : $(free -h | awk '/Mem/{print $2}')"
echo "Timezone          : $(timedatectl 2>/dev/null | awk -F: '/Time zone/{print $2}')"

###############################################################################
section "NETWORK INFORMATION"

printf "%-15s %-8s %-18s %-8s %-8s\n" \
Interface State IP_Address MTU Speed

for IF in $(ls /sys/class/net | grep -v lo)
do
STATE=$(cat /sys/class/net/$IF/operstate)

IP=$(ip -4 addr show $IF | awk '/inet /{print $2}')

MTU=$(cat /sys/class/net/$IF/mtu)

SPEED=$(cat /sys/class/net/$IF/speed 2>/dev/null)

printf "%-15s %-8s %-18s %-8s %-8s\n" \
"$IF" "$STATE" "$IP" "$MTU" "${SPEED:-Unknown}"

done

echo
echo "Default Gateway"
ip route | grep default

echo
echo "Routing Table"
ip route

echo
echo "DNS"
cat /etc/resolv.conf
storage_mapping()
{
echo
echo "==============================================================================================================================================================================="
printf "%-15s %-15s %-10s %-20s %-10s %-20s %-18s %-36s %-40s\n" \
"LV_NAME" "VG_NAME" "LV_SIZE" "MOUNT_POINT" "FSTYPE" \
"PV_DEVICE" "MP_ALIAS" "WWID" "ISCSI_TARGET"


echo "==============================================================================================================================================================================="
echo "==============================================================================================================================================================================="
health_analysis()
{
CRITICAL=0
WARNING=0
INFO=0

echo
echo "====================================================================================="
echo "                    EXECUTIVE HEALTH ANALYSIS"
	health_analysis
echo "====================================================================================="

###############################################################################
# Multipath
###############################################################################

FAILED=$(multipath -ll 2>/dev/null | egrep -ci 'failed|faulty')

if [ "$FAILED" -gt 0 ]; then
    echo "[CRITICAL] Multipath : $FAILED failed/faulty paths detected"
    echo "           Cause  : SAN path failure"
    echo "           Remedy : Check SAN switch, HBA, cables and storage ports."
    ((CRITICAL++))
else
    echo "[INFO] Multipath : All paths healthy"
    ((INFO++))
fi

###############################################################################
# iSCSI
###############################################################################

SESS=$(iscsiadm -m session 2>/dev/null | wc -l)

if [ "$SESS" -eq 0 ]; then
    echo "[CRITICAL] iSCSI : No active sessions"
    echo "           Remedy : Restart iscsid and verify storage connectivity."
    ((CRITICAL++))
else
    echo "[INFO] iSCSI : $SESS active session(s)"
    ((INFO++))
fi

###############################################################################
# multipathd
###############################################################################

systemctl is-active multipathd >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "[CRITICAL] multipathd service is NOT running"
    echo "           Remedy : systemctl restart multipathd"
    ((CRITICAL++))
else
    echo "[INFO] multipathd service running"
    ((INFO++))
fi

###############################################################################
# iscsid
###############################################################################

systemctl is-active iscsid >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "[CRITICAL] iscsid service NOT running"
    echo "           Remedy : systemctl restart iscsid"
    ((CRITICAL++))
else
    echo "[INFO] iscsid service running"
    ((INFO++))
fi

###############################################################################
# Filesystem
###############################################################################

df -P | awk 'NR>1 {gsub("%","",$5); if($5>=90) print $6,$5}' |
while read FS USE
do
    echo "[WARNING] Filesystem $FS is ${USE}% utilized"
    echo "           Recommendation : Extend filesystem or delete unused data."
done

FSWARN=$(df -P | awk 'NR>1 {gsub("%","",$5); if($5>=90)c++} END{print c+0}')
WARNING=$((WARNING+FSWARN))

###############################################################################
# Memory
###############################################################################

MEM=$(free | awk '/Mem/{printf("%d",$3/$2*100)}')

if [ "$MEM" -ge 90 ]; then
    echo "[WARNING] Memory utilization ${MEM}%"
    echo "           Recommendation : Investigate memory consuming processes."
    ((WARNING++))
else
    ((INFO++))
fi

###############################################################################
# Swap
###############################################################################

SWAP=$(free | awk '/Swap/ && $2>0 {printf("%d",$3/$2*100)}')

if [ -n "$SWAP" ] && [ "$SWAP" -ge 50 ]; then
    echo "[WARNING] Swap utilization ${SWAP}%"
    echo "           Recommendation : Review application memory usage."
    ((WARNING++))
fi

###############################################################################
# Network
###############################################################################

for IF in $(ls /sys/class/net | grep -v lo)
do
    STATE=$(cat /sys/class/net/$IF/operstate)

    if [ "$STATE" != "up" ]; then
        echo "[WARNING] Interface $IF is DOWN"
        echo "           Recommendation : Verify cable/bond/VLAN."
        ((WARNING++))
    fi
done

###############################################################################
# Failed Services
###############################################################################

FAILED_SERVICES=$(systemctl --failed --no-legend | wc -l)

if [ "$FAILED_SERVICES" -gt 0 ]; then
    echo "[WARNING] $FAILED_SERVICES failed systemd service(s)"
    echo "           Recommendation : systemctl --failed"
    ((WARNING++))
fi

###############################################################################
# Load Average
###############################################################################

LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
CPU=$(nproc)

LOADINT=$(printf "%.0f" "$LOAD")

if [ "$LOADINT" -gt "$CPU" ]; then
    echo "[WARNING] High system load ($LOAD)"
    echo "           Recommendation : Investigate CPU intensive processes."
    ((WARNING++))
fi

###############################################################################
# Overall Health
###############################################################################

echo
echo "====================================================================================="
echo "SUMMARY"
echo "====================================================================================="

if [ "$CRITICAL" -gt 0 ]; then
    STATUS="CRITICAL"
elif [ "$WARNING" -gt 0 ]; then
    STATUS="WARNING"
else
    STATUS="HEALTHY"
fi

echo "Overall Health : $STATUS"
echo
echo "Critical Issues : $CRITICAL"
echo "Warning Issues  : $WARNING"
echo "Information     : $INFO"

echo
}
echo "==============================================================================================================================================================================="

lvs --noheadings --separator="|" -o lv_name,vg_name,lv_size |
while IFS="|" read LV VG SIZE
do
    LV=$(echo "$LV" | xargs)
    VG=$(echo "$VG" | xargs)
    SIZE=$(echo "$SIZE" | xargs)

    LVPATH="/dev/${VG}/${LV}"

    MP=$(findmnt -nr -S "$LVPATH" -o TARGET)

    FSTYPE=$(findmnt -nr -S "$LVPATH" -o FSTYPE)

    PV=$(pvs --noheadings -o pv_name -S vg_name="$VG" | head -1 | xargs)

    MP_ALIAS=$(basename "$PV")

    WWID=$(multipath -ll 2>/dev/null | awk -v mp="$MP_ALIAS" '
        $1==mp {getline; print $1}
    ')

    SD=$(multipath -ll 2>/dev/null | awk -v mp="$MP_ALIAS" '
        $1==mp {f=1}
        f && /sd[a-z]/ {print $3; exit}
        /^$/ {f=0}
    ')

    TARGET=""

    if [ -n "$SD" ]; then
        HCTL=$(lsscsi | awk -v d="$SD" '$NF=="/dev/"d {print $1}' | tr -d '[]')
        HOST=$(echo "$HCTL" | cut -d: -f1)

        TARGET=$(iscsiadm -m session -P 3 2>/dev/null | awk -v h="$HOST" '
            /Host Number:/ {host=$3}
            /Target:/ && host==h {print $2; exit}
        ')
    fi

    printf "%-15s %-15s %-10s %-20s %-10s %-20s %-18s %-36s %-40s\n" \
    "$LV" "$VG" "$SIZE" "${MP:--}" "${FSTYPE:--}" \
    "$PV" "$MP_ALIAS" "$WWID" "${TARGET:--}"

done

echo "==============================================================================================================================================================================="
}

###############################################################################
section "FILESYSTEM INFORMATION"

df -hT

###############################################################################
section "LVM DETAILS"

pvs 2>/dev/null

echo
vgs 2>/dev/null

echo
lvs -o lv_name,vg_name,lv_size,data_percent,lv_attr 2>/dev/null
section "LVM -> PV -> Multipath -> WWID -> iSCSI Mapping"

storage_mapping

###############################################################################
section "BLOCK DEVICES"

lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT

###############################################################################
section "UUID INFORMATION"

blkid

###############################################################################
section "iSCSI INFORMATION"

echo "iscsid Service"
systemctl is-active iscsid 2>/dev/null

echo
echo "iscsiadm Sessions"
iscsiadm -m session 2>/dev/null || echo "No Sessions"

echo
echo "Configured Nodes"
iscsiadm -m node 2>/dev/null

###############################################################################
section "MULTIPATH INFORMATION"

echo "multipathd Service"
systemctl is-active multipathd 2>/dev/null

echo
multipath -ll 2>/dev/null

###############################################################################
section "SCSI DEVICES"

lsscsi 2>/dev/null

###############################################################################
section "FIBRE CHANNEL"

for H in /sys/class/fc_host/host*
do

[ -d "$H" ] || continue

echo "Host              : $(basename $H)"
echo "WWPN              : $(cat $H/port_name)"
echo "WWNN              : $(cat $H/node_name)"
echo "Port State        : $(cat $H/port_state)"
echo "Speed             : $(cat $H/speed)"
echo

done

###############################################################################
section "RUNNING SERVICES"

systemctl list-units --type=service --state=running --no-pager

###############################################################################
section "FAILED SERVICES"

systemctl --failed --no-pager

###############################################################################
section "ENABLED SERVICES"

systemctl list-unit-files --type=service --state=enabled --no-pager

###############################################################################
section "MEMORY"

free -h

###############################################################################
section "SWAP"

swapon --show

###############################################################################
section "LOAD AVERAGE"

uptime

###############################################################################
section "TOP CPU"

ps -eo pid,user,comm,%cpu --sort=-%cpu | head

###############################################################################
section "TOP MEMORY"

ps -eo pid,user,comm,%mem --sort=-%mem | head

###############################################################################
section "OPEN TCP PORTS"

ss -tulpn

###############################################################################
section "LAST REBOOT"

last reboot | head

###############################################################################
section "LAST LOGIN"

last | head

###############################################################################
section "END OF REPORT"

echo
echo "Report Generated Successfully."
echo "File : $REPORT"
