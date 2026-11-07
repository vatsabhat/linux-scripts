#!/bin/bash
# Description: Gathers active multipath LUN IDs and sizes on RHEL 10
# Output Format: Table

printf "%-25s %-15s %-15s %-10s\n" "MULTIPATH MAP" "LUN ID (WWID)" "SIZE" "STATUS"
printf "%-25s %-15s %-15s %-10s\n" "------------- " "------------ " "----" "------"

# Loop through active maps
multipath -ll -v1 | while read -r map; do
    if [ ! -z "$map" ]; then
        # Gather WWID/LUN ID
        wwid=$(multipath -ll "$map" | grep -E "$map" | awk '{print $2}' | tr -d '()')
        
        # Gather Size
        size=$(multipath -ll "$map" | grep -m1 "size=" | awk -F'size=' '{print $2}' | awk '{print $1}')
        
        # Determine Status
        if multipath -ll "$map" | grep -q "faulty\|failed"; then
            status="Degraded"
        else
            status="Optimal"
        fi
        
        printf "%-25s %-15s %-15s %-10s\n" "$map" "$wwid" "$size" "$status"
    fi
done
