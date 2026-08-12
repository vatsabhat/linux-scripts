#!/bin/bash

# Define output file
OUTPUT_FILE="/tmp/linux_audit_report_$(date +%F_%H%M%S).txt"

# Helper function to print table headers
print_header() {
    local title="$1"
    echo -e "\n\n+---------------------------------------------------------------------------------+" >> "$OUTPUT_FILE"
    printf "| %-79s |\n" "$title" >> "$OUTPUT_FILE"
    echo "+---------------------------------------------------------------------------------+" >> "$OUTPUT_FILE"
}

echo "=================================================================================" >> "$OUTPUT_FILE"
echo "                           LINUX SERVER AUDIT REPORT                             " >> "$OUTPUT_FILE"
echo "                           Generated on: $(date)                        " >> "$OUTPUT_FILE"
echo "=================================================================================" >> "$OUTPUT_FILE"

# 1. SYSTEM & HARDWARE INFORMATION
print_header "1. SYSTEM & HARDWARE INFORMATION"
printf "| %-35s | %-41s |\n" "Metric" "Value" >> "$OUTPUT_FILE"
echo "+-------------------------------------+-------------------------------------------+" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "Hostname" "$(hostname)" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "OS Release" "$(hostnamectl | grep -i 'Operating System' | cut -d: -f2 | xargs)" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "Kernel Version" "$(uname -r)" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "Uptime" "$(uptime -p)" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "CPU Model" "$(lscpu | grep 'Model name' | cut -d: -f2 | xargs)" >> "$OUTPUT_FILE"
printf "| %-35s | %-41s |\n" "CPU Cores" "$(nproc)" >> "$OUTPUT_FILE"
echo "+-------------------------------------+-------------------------------------------+" >> "$OUTPUT_FILE"

echo -e "\n* Memory Status:" >> "$OUTPUT_FILE"
free -h | awk '
    BEGIN {print "+-------------+-------------+-------------+-------------+-------------+-------------+\n| Type        | Total       | Used        | Free        | Shared      | Buff/Cache  |\n+-------------+-------------+-------------+-------------+-------------+-------------+"}
    /Mem:/ {printf "| Memory      | %-11s | %-11s | %-11s | %-11s | %-11s |\n", $2, $3, $4, $5, $6}
    /Swap:/ {printf "| Swap        | %-11s | %-11s | %-11s |             |             |\n", $2, $3, $4}
    END {print "+-------------+-------------+-------------+-------------+-------------+-------------+"}
' >> "$OUTPUT_FILE"


# 2. STORAGE & FILESYSTEMS
print_header "2. STORAGE & FILESYSTEMS"
echo "* Physical Block Devices:" >> "$OUTPUT_FILE"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT | awk '
    BEGIN {print "+------------+------------+------------+-------------------------------------+\n| Name       | FSTYPE     | Size       | Mountpoint                          |\n+------------+------------+------------+-------------------------------------+"}
    NR>1 {printf "| %-10s | %-10s | %-10s | %-35s |\n", $1, $2, $3, $4}
    END {print "+------------+------------+------------+-------------------------------------+"}
' >> "$OUTPUT_FILE"

echo -e "\n* Mounted Filesystems (Disk Usage):" >> "$OUTPUT_FILE"
df -hT -x tmpfs -x devtmpfs | awk '
    BEGIN {print "+----------------------+----------+-------+-------+-------+------+------------+\n| Filesystem           | Type     | Size  | Used  | Avail | Use% | Mounted on |\n+----------------------+----------+-------+-------+-------+------+------------+"}
    NR>1 {printf "| %-20s | %-8s | %-5s | %-5s | %-5s | %-4s | %-10s |\n", $1, $2, $3, $4, $5, $6, $7}
    END {print "+----------------------+----------+-------+-------+-------+------+------------+"}
' >> "$OUTPUT_FILE"


# 3. NETWORK & NETWORK FILESYSTEMS (NFS/Samba)
print_header "3. NETWORK & NETWORK FILESYSTEMS"
echo "* Interface IP Addresses:" >> "$OUTPUT_FILE"
ip -br addr | awk '
    BEGIN {print "+------------+--------+-------------------------------------------------------+\n| Interface  | Status | IP Address                                            |\n+------------+--------+-------------------------------------------------------+"}
    {printf "| %-10s | %-6s | %-53s |\n", $1, $2, $3" "$4" "$5}
    END {print "+------------+--------+-------------------------------------------------------+"}
' >> "$OUTPUT_FILE"

echo -e "\n* Mounted Network Filesystems (NFS/CIFS/Gluster):" >> "$OUTPUT_FILE"
NET_FS=$(mount | grep -E 'nfs|cifs|gluster')
if [ -z "$NET_FS" ]; then
    echo -e "+---------------------------------------------------------------------------------+\n| No network filesystems currently mounted.                                       |\n+---------------------------------------------------------------------------------+" >> "$OUTPUT_FILE"
else
    echo "$NET_FS" | awk '
        BEGIN {print "+---------------------------+---------------------------+---------------------+\n| Source                    | Target                    | Type                |\n+---------------------------+---------------------------+---------------------+"}
        {printf "| %-25s | %-25s | %-19s |\n", $1, $3, $5}
        END {print "+---------------------------+---------------------------+---------------------+"}
    ' >> "$OUTPUT_FILE"
fi


# 4. IMPORTANT CONFIGURATION FILES
print_header "4. IMPORTANT CONFIGURATION FILES"
echo "* Active Rules in /etc/fstab:" >> "$OUTPUT_FILE"
grep -v '^#' /etc/fstab | grep -v '^$' | awk '
    BEGIN {print "+-------------------------------------+-----------------+--------+------------+\n| Device / UUID                       | Mount Point     | Type   | Options    |\n+-------------------------------------+-----------------+--------+------------+"}
    {printf "| %-35s | %-15s | %-6s | %-10s |\n", $1, $2, $3, $4}
    END {print "+-------------------------------------+-----------------+--------+------------+"}
' >> "$OUTPUT_FILE"

echo -e "\n* Name Servers (/etc/resolv.conf):" >> "$OUTPUT_FILE"
grep -v '^#' /etc/resolv.conf | grep -v '^$' | awk '
    BEGIN {print "+------------------------+----------------------------------------------------+ \n| Configuration          | Value                                              |\n+------------------------+----------------------------------------------------+"}
    {printf "| %-22s | %-50s |\n", $1, $2}
    END {print "+------------------------+----------------------------------------------------+"}
' >> "$OUTPUT_FILE"


# 5. RUNNING SYSTEMD SERVICES
print_header "5. RUNNING SYSTEMD SERVICES"
systemctl list-units --type=service --state=running --no-legend | awk '
    BEGIN {print "+-----------------------------------------+----------+------------------------+\n| Service Unit Name                       | Sub-State| Description            |\n+-----------------------------------------+----------+------------------------+"}
    {
        # Capture description dynamically if it spans multiple ending fields
        desc=""; for(i=5; i<=NF; i++) desc=desc $i " ";
        printf "| %-39s | %-8s | %-22s |\n", $1, $4, substr(desc, 1, 22)
    }
    END {print "+-----------------------------------------+----------+------------------------+"}
' >> "$OUTPUT_FILE"


# 6. SECURITY STATUS & USERS
print_header "6. SECURITY STATUS & USER AUDIT"
echo "* LSM Modules Status:" >> "$OUTPUT_FILE"
echo "+-------------------------------------+-------------------------------------------+" >> "$OUTPUT_FILE"
if command -v getenforce &> /dev/null; then
    printf "| %-35s | %-41s |\n" "SELinux Status" "$(getenforce)" >> "$OUTPUT_FILE"
elif command -v aa-status &> /dev/null; then
    printf "| %-35s | %-41s |\n" "AppArmor Status" "Active (Run aa-status as root)" >> "$OUTPUT_FILE"
else
    printf "| %-35s | %-41s |\n" "SELinux/AppArmor" "Not Found / Not Active" >> "$OUTPUT_FILE"
fi
echo "+-------------------------------------+-------------------------------------------+" >> "$OUTPUT_FILE"

echo -e "\n* Open Listening Ports:" >> "$OUTPUT_FILE"
ss -tuln | awk '
    BEGIN {print "+---------+-------+-------------------------+---------------------------------+\n| Netid   | State | Local Address:Port      | Peer Address:Port               |\n+---------+-------+-------------------------+---------------------------------+"}
    NR>1 {printf "| %-7s | %-5s | %-23s | %-31s |\n", $1, $2, $5, $6}
    END {print "+---------+-------+-------------------------+---------------------------------+"}
' >> "$OUTPUT_FILE"

echo -e "\n* Privileged Accounts (UID 0):" >> "$OUTPUT_FILE"
awk -F: '$3 == 0 {print $1}' /etc/passwd | awk '
    BEGIN {print "+-----------------------------------------------------------------------------+\n| Root Account Names                                                          |\n+-----------------------------------------------------------------------------+"}
    {printf "| %-75s |\n", $1}
    END {print "+-----------------------------------------------------------------------------+"}
' >> "$OUTPUT_FILE"

echo -e "\n* Non-System Regular Users (UID >= 1000):" >> "$OUTPUT_FILE"
awk -F: '$3 >= 1000 && $1 != "nobody" {printf "%s:%s:%s:%s\n", $1, $3, $6, $7}' /etc/passwd | awk -F: '
    BEGIN {print "+-----------------+-------+---------------------------------+-----------------+\n| Username        | UID   | Home Directory                  | Login Shell     |\n+-----------------+-------+---------------------------------+-----------------+"}
    {printf "| %-15s | %-5s | %-31s | %-15s |\n", $1, $2, $3, $4}
    END {print "+-----------------+-------+---------------------------------+-----------------+"}
' >> "$OUTPUT_FILE"

echo "=================================================================================" >> "$OUTPUT_FILE"
echo "Audit complete. Results saved to: $OUTPUT_FILE"
echo "================================================================================="
