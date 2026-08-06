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
#exec (tee "$REPORT")

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
section "INSTALLED SOFTWARE"
installed_packages_report
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

echo "=========================================="

###############################################################################
# SOFTWARE INVENTORY
###############################################################################

software_inventory()
{

section "SOFTWARE INVENTORY"

###############################################################################
# Function
###############################################################################

print_category()
{
CATEGORY="$1"
PATTERN="$2"

echo
echo "============================================================================="
printf "%s\n" "$CATEGORY"
echo "============================================================================="

printf "%-45s %-20s %-30s\n" "PACKAGE" "VERSION" "VENDOR"
printf "%-45s %-20s %-30s\n" "---------------------------------------------" "--------------------" "------------------------------"

FOUND=0

rpm -qa | sort | egrep -i "$PATTERN" | while read PKG
do
    VER=$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$PKG" 2>/dev/null)
    VEN=$(rpm -q --qf "%{VENDOR}" "$PKG" 2>/dev/null)

    printf "%-45s %-20s %-30s\n" "$PKG" "$VER" "$VEN"
    FOUND=1
done

COUNT=$(rpm -qa | egrep -ic "$PATTERN")

if [ "$COUNT" -eq 0 ]
then
    echo "No Packages Found."
fi

echo
echo "Package Count : $COUNT"

}

###############################################################################
# 1 Operating System
###############################################################################

print_category \
"Operating System" \
"^kernel|bash|glibc|systemd|util-linux|filesystem|setup|redhat-release"

###############################################################################
# 2 Kernel Packages
###############################################################################

print_category \
"Kernel Packages" \
"^kernel"

###############################################################################
# 3 Storage & Filesystem
###############################################################################

print_category \
"Storage & Filesystem" \
"lvm|device-mapper|multipath|iscsi|xfs|e2fs|mdadm|parted|gdisk|nvme|sg3|smart|dracut"

###############################################################################
# 4 SAN / Multipath / iSCSI
###############################################################################

print_category \
"SAN / Multipath / iSCSI" \
"multipath|iscsi|device-mapper|sg3|nvme"

###############################################################################
# 5 Fibre Channel Drivers
###############################################################################

print_category \
"Fibre Channel / HBA" \
"lpfc|qla|emulex|fcoe|bnx2fc|qlogic|hpsa|mpt3sas|megaraid"

###############################################################################
# 6 Networking
###############################################################################

print_category \
"Networking" \
"network|NetworkManager|iproute|net-tools|ethtool|bind|tcpdump|curl|wget|openssh|dhcp"

###############################################################################
# 7 Security
###############################################################################

print_category \
"Security" \
"selinux|audit|aide|openssl|openscap|fapolicyd|gnutls"

###############################################################################
# 8 Containers
###############################################################################

print_category \
"Containers" \
"podman|docker|containerd|cri-o|buildah|skopeo"

###############################################################################
# 9 Virtualization
###############################################################################

print_category \
"Virtualization" \
"libvirt|virt|qemu|kvm|cockpit-machines|ovirt"

###############################################################################
# 10 High Availability
###############################################################################

print_category \
"High Availability / Cluster" \
"pacemaker|pcs|corosync|resource-agents|fence"

###############################################################################
# 11 Monitoring
###############################################################################

print_category \
"Monitoring / Logging" \
"sysstat|tuned|collectd|telegraf|grafana|prometheus|node-exporter|sos|insights|rsyslog"

###############################################################################
# 12 Backup
###############################################################################

print_category \
"Backup & Recovery" \
"rear|borg|bacula|amanda|veeam|netbackup|commvault"

###############################################################################
# 13 Database
###############################################################################

print_category \
"Database" \
"oracle|mysql|mariadb|postgres|mongodb|redis"

###############################################################################
# 14 Web Server
###############################################################################

print_category \
"Web / Application Server" \
"httpd|nginx|apache|tomcat|jboss|wildfly"

###############################################################################
# 15 Automation
###############################################################################

print_category \
"Automation" \
"ansible|chef|puppet|salt"

###############################################################################
# 16 Development
###############################################################################

print_category \
"Development Tools" \
"gcc|gcc-c|make|cmake|perl|python|java|git"

###############################################################################
# 17 Cloud Agents
###############################################################################

print_category \
"Cloud / Virtualization Agents" \
"open-vm-tools|hyperv|cloud-init|walinuxagent|amazon|google"

###############################################################################
# 18 Storage Vendor Utilities
###############################################################################

print_category \
"HPE / Dell / IBM / NetApp / Pure Storage Utilities" \
"hpe|hp-|ssacli|storcli|perccli|megacli|ibm|emc|netapp|pure"

###############################################################################
# 19 Third Party Packages
###############################################################################

echo
echo "============================================================================="
echo "Third Party Packages"
echo "============================================================================="

rpm -qa --qf "%{NAME}|%{VERSION}-%{RELEASE}|%{VENDOR}\n" |
grep -vi "Red Hat" |
column -t -s "|"

###############################################################################
# 20 Recently Installed
###############################################################################

echo
echo "============================================================================="
echo "Recently Installed Packages"
echo "============================================================================="

rpm -qa --last | head -50

###############################################################################
# Summary
###############################################################################

echo
echo "============================================================================="
echo "SOFTWARE SUMMARY"
echo "============================================================================="

echo "Total Installed RPMs : $(rpm -qa | wc -l)"

echo "Kernel Packages      : $(rpm -qa | grep '^kernel' | wc -l)"

echo "Third Party Packages : $(rpm -qa --qf '%{VENDOR}\n' | grep -v 'Red Hat' | wc -l)"

}

echo "========================================="

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
#########
###############################################################################
# FUNCTION : Installed Software by Category
###############################################################################

section "SOFTWARE INVENTORY"

software_inventory

installed_packages_report()
{
section "INSTALLED SOFTWARE INVENTORY"

declare -A CATEGORY

CATEGORY["Operating System"]="kernel kernel-core kernel-modules kernel-modules-extra bash glibc systemd util-linux"
CATEGORY["Storage"]="lvm2 device-mapper device-mapper-multipath multipath-tools iscsi-initiator-utils sg3_utils mdadm xfsprogs e2fsprogs dosfstools gdisk parted nvme-cli smartmontools hdparm"
CATEGORY["SAN / Fibre Channel"]="qla2xxx qlogic lpfc emulex hpsa mpt3sas megaraid_sas bnx2fc fcoe-utils"
CATEGORY["Networking"]="NetworkManager network-scripts iproute net-tools ethtool bind-utils tcpdump nmap traceroute wget curl openssh-server openssh-clients"
CATEGORY["Security"]="selinux-policy selinux-policy-targeted policycoreutils audit audit-libs aide openscap-scanner scap-security-guide fapolicyd openssl"
CATEGORY["Containers"]="podman podman-docker buildah skopeo docker docker-ce containerd cri-o"
CATEGORY["Virtualization"]="qemu-kvm libvirt libvirt-daemon virt-install virt-manager cockpit-machines edk2-ovmf"
CATEGORY["Clustering"]="pcs pacemaker corosync fence-agents resource-agents"
CATEGORY["Monitoring"]="sysstat tuned sos insights-client collectd prometheus-node-exporter grafana-agent"
CATEGORY["Backup"]="rear rsnapshot borgbackup bacula amanda"
CATEGORY["Databases"]="oracle-database mysql-server mariadb-server postgresql-server mongodb"
CATEGORY["Web Servers"]="httpd nginx tomcat"
CATEGORY["Automation"]="ansible ansible-core puppet chef salt salt-minion"
CATEGORY["Development"]="gcc gcc-c++ make cmake git python3 perl java-11-openjdk java-17-openjdk"

for CAT in "${!CATEGORY[@]}"
do
    echo
    echo "============================================================================="
    printf "%s\n" "$CAT"
    echo "============================================================================="

    printf "%-40s %-15s %-30s\n" "PACKAGE" "STATUS" "VERSION"
    printf "%-40s %-15s %-30s\n" "----------------------------------------" "---------------" "------------------------------"

    FOUND=0

    for PKG in ${CATEGORY[$CAT]}
    do
        if rpm -q "$PKG" >/dev/null 2>&1
        then
            VER=$(rpm -q --qf "%{VERSION}-%{RELEASE}\n" "$PKG")
            printf "%-40s %-15s %-30s\n" "$PKG" "Installed" "$VER"
            FOUND=1
        fi
    done

    if [ "$FOUND" -eq 0 ]
    then
        echo "No packages detected."
    fi
done
}

###############################################################################
section "OPEN NETWORK PORTS"
###############################################################################

printf "%-6s %-8s %-22s %-25s %-15s\n" \
"PROTO" "PORT" "LISTEN_IP" "PROCESS" "PID"

ss -tulnp | awk '
NR>1{
split($5,a,":")
port=a[length(a)]
printf "%-6s %-8s %-22s %-25s %-15s\n",$1,port,$5,$7,$6
}'

###############################################################################
section "EXTERNALLY LISTENING PORTS"
###############################################################################

ss -tulnp | awk '

/0.0.0.0|::/{

print

}'

###############################################################################
section "FIREWALL STATUS"
###############################################################################

systemctl status firewalld --no-pager

echo
firewall-cmd --list-all 2>/dev/null

###############################################################################
section "SELINUX"
###############################################################################

getenforce

sestatus

###############################################################################
section "SSH SECURITY"
###############################################################################

grep -Ei \
'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|MaxAuthTries|Protocol' \
/etc/ssh/sshd_config

###############################################################################
section "PASSWORD POLICY"
###############################################################################

grep PASS_MAX_DAYS /etc/login.defs

grep PASS_MIN_DAYS /etc/login.defs

grep PASS_WARN_AGE /etc/login.defs

grep PASS_MIN_LEN /etc/login.defs


###############################################################################
section "AVAILABLE SECURITY UPDATES"
###############################################################################

dnf updateinfo list security

dnf updateinfo info security


###############################################################################
section "KERNEL UPDATE CHECK"
###############################################################################

echo "Running Kernel"

uname -r

echo

echo "Installed Kernels"

rpm -qa kernel\*


###############################################################################
section "SECURITY RECOMMENDATIONS"
###############################################################################

CRITICAL=0
WARNING=0

echo

#######################################
# Firewall
#######################################

systemctl is-active firewalld >/dev/null

if [ $? -ne 0 ]
then
echo "[CRITICAL] Firewalld is NOT running"
((CRITICAL++))
fi

#######################################
# SELinux
#######################################

if [ "$(getenforce)" != "Enforcing" ]
then
echo "[WARNING] SELinux not enforcing"
((WARNING++))
fi

#######################################
# Root Login
#######################################

grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config

if [ $? -eq 0 ]
then
echo "[WARNING] SSH Root Login Enabled"
((WARNING++))
fi

#######################################
# Password Authentication
#######################################

grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config

if [ $? -eq 0 ]
then
echo "[WARNING] Password Authentication Enabled"
((WARNING++))
fi

#######################################
# Open Telnet
#######################################

ss -tulnp | grep ":23 "

if [ $? -eq 0 ]
then
echo "[CRITICAL] Telnet Port Open"
((CRITICAL++))
fi

#######################################
# FTP
#######################################

ss -tulnp | grep ":21 "

if [ $? -eq 0 ]
then
echo "[WARNING] FTP Port Open"
((WARNING++))
fi

#######################################
# Security Updates
#######################################

UPDATES=$(dnf updateinfo list security 2>/dev/null | wc -l)

if [ "$UPDATES" -gt 0 ]
then
echo "[WARNING] $UPDATES security updates available"
((WARNING++))
fi

#######################################
# Summary
#######################################

echo
echo "Security Score"

TOTAL=100

SCORE=$((TOTAL-(CRITICAL*20)-(WARNING*5)))

echo "$SCORE /100"

echo

echo "Recommendations"

echo "--------------------------------"

[ $CRITICAL -gt 0 ] && echo "• Apply critical security fixes immediately."

[ $WARNING -gt 0 ] && echo "• Review security configuration."

echo "• Keep OS updated."

echo "• Enable automatic security patching."

echo "• Disable unused services."

echo "• Close unnecessary network ports."

echo "• Use SSH Keys instead of passwords."

echo "• Keep SELinux in Enforcing mode."

echo "• Enable firewalld."

echo "• Review failed login attempts."

echo "• Audit sudo access."

echo "=================================================="
