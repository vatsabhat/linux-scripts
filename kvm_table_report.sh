#!/bin/bash

# Define table columns and formatting
# Adjust numbers if your VM names or network configs are exceptionally long
FORMAT="│ %-25s │ %-15s │ %-35s │ %-18s │\n"

# Draw top border
printf "┌───────────────────────────┬─────────────────┬─────────────────────────────────────┬────────────────────┐\n"
printf "$FORMAT" "VM Name" "Disk Size" "Network Card" "IP Address"
printf "├───────────────────────────┼─────────────────┼─────────────────────────────────────┼────────────────────┤\n"

# Get all VMs (running and powered off)
for vm in $(virsh list --all --name); do
    # Skip empty lines
    [ -z "$vm" ] && continue

    # Check execution state
    state=$(virsh domstate "$vm")

    # Calculate total virtual disk size
    disks=$(virsh domblklist "$vm" --details | awk '$1=="disk" {print $2}')
    total_size=0
    for disk in $disks; do
        if [[ -f "$disk" ]]; then
            size=$(qemu-img info "$disk" | grep "virtual size" | sed 's/.*(\(.* bytes\)/\1/' | awk '{print $1}')
            size_gb=$((size / 1024 / 1024 / 1024))
            total_size=$((total_size + size_gb))
        fi
    done
    disk_display="${total_size} GB"

    # Fetch interface type and host source
    net_info=$(virsh domiflist "$vm" | awk 'NR>2 {print $3 ":" $4}' | tr '\n' ',' | sed 's/,$//')
    [ -z "$net_info" ] && net_info="None"

    # Query IP routing data
    if [ "$state" = "running" ]; then
        ip_addr=$(virsh domifaddr "$vm" --source agent 2>/dev/null | awk 'NR>2 {print $4}' | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
        if [ -z "$ip_addr" ]; then
            ip_addr=$(virsh domifaddr "$vm" --source lease 2>/dev/null | awk 'NR>2 {print $4}' | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
        fi
        [ -z "$ip_addr" ] && ip_addr="Unknown"
    else
        ip_addr="Offline"
    fi

    # Print the table row
    printf "$FORMAT" "$vm" "$disk_display" "$net_info" "$ip_addr"
done

# Draw bottom border
printf "└───────────────────────────┴─────────────────┴─────────────────────────────────────┴────────────────────┘\n"
