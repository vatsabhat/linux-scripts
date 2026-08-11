#!/bin/bash
# Print a clean, formatted table of all systemd services
HOSTNAME=$(hostname)
CURRENT_DATE=$(date +%Y-%m-%d)
printf "$HOSTNAME"
printf "$CURRENT_DATE"
systemctl list-units --type=service --all --no-legend --no-pager | \
awk '{
    printf "%-40s | %-10s | %-10s | %-10s | ", $1, $2, $3, $4
    $1=$2=$3=$4=""; sub(/^[ \t]+/, ""); print $0
}' | \
(printf "%-40s | %-10s | %-10s | %-10s | %s\n" "UNIT" "LOAD" "ACTIVE" "SUB" "DESCRIPTION"
 printf "%s\n" "------------------------------------------------------------------------------------------------------------------"
 cat)
