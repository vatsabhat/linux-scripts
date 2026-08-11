#!/bin/bash
#### SCRIPT TO LIST MULTIPATH DEVICES AND ITS ALIAS AND STATUS AS WELL #####
echo "Hostname : $(hostname)"
echo "Date     : $(date '+%F %T')"
echo

printf "%-20s %-36s %-10s %-12s\n" "ALIAS" "WWID" "TYPE" "STATUS"
printf "%-20s %-36s %-10s %-12s\n" "--------------------" "------------------------------------" "----------" "------------"

multipath -ll | awk '
BEGIN{
    green="\033[1;32m"
    blue="\033[1;34m"
    red="\033[1;31m"
    reset="\033[0m"
}

# Multipath header
$2 ~ /^\(/ {
    alias=$1
    wwid=$2
    gsub(/[()]/,"",wwid)
    next
}

# Path group status
/status=/ {
    split($0,a,"status=")
    stat=a[2]

    if(stat=="active")
        color=green
    else if(stat=="enabled")
        color=blue
    else
        color=red

    printf "%-20s %-36s %-10s %s%-10s%s\n", \
           alias, wwid, "GROUP", color, stat, reset
    next
}

# Failed/Faulty paths
/failed/ || /faulty/ {

    if($0 ~ /status=/)
        next

    disk=""

    for(i=1;i<=NF;i++)
        if($i ~ /^sd[a-z]+$/)
            disk=$i

    if(disk!="")
        printf "%-20s %-36s %-10s %sFAILED%s\n", \
               alias, wwid, disk, red, reset
}'
