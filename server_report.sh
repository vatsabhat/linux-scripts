#!/bin/bash

# Ensure the script is run as root for full hardware/subscription details
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to fetch complete information."
  exit 1
fi

# Define formatting helpers
SEPARATOR="=========================================================================================="
HEADER_FORMAT="%-30s | %-55s\n"
ROW_FORMAT="%-30s | %-55s\n"

print_header() {
    echo -e "\n$SEPARATOR"
    echo -e "  PAGE $1: $2"
    echo -e "$SEPARATOR"
    printf "$HEADER_FORMAT" "Component/Property" "Details"
    echo -e "-------------------------------|----------------------------------------------------------"
}

# ==========================================
# PAGE 1: SYSTEM & HARDWARE OVERVIEW
# ==========================================
print_header "1" "SYSTEM & HARDWARE OVERVIEW"

printf "$ROW_FORMAT" "Hostname" "$(hostname)"
printf "$ROW_FORMAT" "Manufacturer" "$(dmidecode -s system-manufacturer 2>/dev/null || echo 'N/A')"
printf "$ROW_FORMAT" "Product Name" "$(dmidecode -s system-product-name 2>/dev/null || echo 'N/A')"
printf "$ROW_FORMAT" "Serial Number" "$(dmidecode -s system-serial-number 2>/dev/null || echo 'N/A')"
printf "$ROW_FORMAT" "BIOS Version" "$(dmidecode -s bios-version 2>/dev/null || echo 'N/A')"
printf "$ROW_FORMAT" "BIOS Release Date" "$(dmidecode -s bios-release-date 2>/dev/null || echo 'N/A')"
printf "$ROW_FORMAT" "CPU Model" "$(lscpu | grep 'Model name:' | sed 's/Model name:[ \t]*//')"
printf "$ROW_FORMAT" "CPU Cores / Threads" "$(lscpu | grep 'CPU(s):' | head -n1 | awk '{print $2}') Cores / $(lscpu | grep 'Thread(s) per core:' | awk '{print $4}') Threads per Core"
printf "$ROW_FORMAT" "Total Memory" "$(free -h | grep Mem: | awk '{print $2}')"

# ==========================================
# PAGE 2: OPERATING SYSTEM & KERNEL
# ==========================================
print_header "2" "OPERATING SYSTEM & KERNEL"

if [ -f /etc/os-release ]; then
    OS_NAME=$(grep -w "NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION=$(grep -w "VERSION" /etc/os-release | cut -d= -f2 | tr -d '"')
else
    OS_NAME="Unknown Linux"
    OS_VERSION="N/A"
fi

printf "$ROW_FORMAT" "OS Name" "$OS_NAME"
printf "$ROW_FORMAT" "OS Version" "$OS_VERSION"
printf "$ROW_FORMAT" "Kernel Version" "$(uname -r)"
printf "$ROW_FORMAT" "Architecture" "$(uname -m)"
printf "$ROW_FORMAT" "Boot Time" "$(uptime -s)"
printf "$ROW_FORMAT" "Uptime" "$(uptime -p)"
printf "$ROW_FORMAT" "Default Runlevel/Target" "$(systemctl get-default 2>/dev/null || runlevel | awk '{print $2}')"
printf "$ROW_FORMAT" "Timezone" "$(timedatectl | grep "Time zone" | awk '{print $3}')"

# ==========================================
# PAGE 3: NETWORKING & STORAGE
# ==========================================
print_header "3" "NETWORKING & STORAGE"

# Get primary IP and interface
PRIMARY_INT=$(ip route | grep default | awk '{print $5}' | head -n1)
PRIMARY_IP=$(ip addr show dev "$PRIMARY_INT" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -n1)

printf "$ROW_FORMAT" "Primary Interface" "${PRIMARY_INT:-N/A}"
printf "$ROW_FORMAT" "Primary IP Address" "${PRIMARY_IP:-N/A}"
printf "$ROW_FORMAT" "Gateway" "$(ip route | grep default | awk '{print $3}' | head -n1)"
printf "$ROW_FORMAT" "DNS Servers" "$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd, -)"

# Storage Layout Summary
printf "$ROW_FORMAT" "Disk List" "$(lsblk -d -n -o NAME,SIZE | tr '\n' ',' | sed 's/,$//')"
printf "$ROW_FORMAT" "Root Partition Size" "$(df -h / | awk 'NR==2 {print $2}')"
printf "$ROW_FORMAT" "Root Partition Usage" "$(df -h / | awk 'NR==2 {print $5}')"

# ==========================================
# PAGE 4: SECURITY, USERS & ENVIRONMENT
# ==========================================
print_header "4" "SECURITY, USERS & ENVIRONMENT"

# Check Firewall Status
if systemctl is-active --quiet ufw; then FW="UFW (Active)"; elif systemctl is-active --quiet firewalld; then FW="Firewalld (Active)"; else FW="Inactive/None"; fi

# Check SELinux / AppArmor
if command -v getenforce >/dev/null; then SEC_MOD="SELinux ($(getenforce))"; elif [ -d /etc/apparmor.d ]; then SEC_MOD="AppArmor (Enabled)"; else SEC_MOD="None"; fi

printf "$ROW_FORMAT" "Firewall Status" "$FW"
printf "$ROW_FORMAT" "Security Module" "$SEC_MOD"
printf "$ROW_FORMAT" "SSH Port" "$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22 (Default)")"
printf "$ROW_FORMAT" "Total Local Users" "$(wc -l < /etc/passwd)"
printf "$ROW_FORMAT" "Logged-in Users" "$(who | awk '{print $1}' | sort -u | paste -sd, -)"
printf "$ROW_FORMAT" "Installed Packages (Count)" "$(dpkg-query -l 2>/dev/null | wc -l || rpm -qa 2>/dev/null | wc -l || echo 'N/A')"
echo -e "$SEPARATOR\n"
