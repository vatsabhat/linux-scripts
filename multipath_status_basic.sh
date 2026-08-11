#!/bin/bash
###############################################################################
# Script Name : multipath_status.sh
# Description : Display Multipath Path Status with Summary
# Compatible  : RHEL 7 / RHEL 8 / RHEL 9
###############################################################################

echo
echo "==============================================================="
echo "               MULTIPATH PATH HEALTH REPORT"
echo "==============================================================="
echo "Hostname : $(hostname)"
echo "Date     : $(date '+%F %T')"
echo

multipath -ll | awk '

BEGIN{

    green="\033[1;32m"
    blue="\033[1;34m"
    red="\033[1;31m"
    yellow="\033[1;33m"
    reset="\033[0m"

    good=0
    bad=0
}

########################################################################
# Multipath Device Header
########################################################################
$2 ~ /^\(/ {

    alias=$1
    wwid=$2

    gsub(/[()]/,"",wwid)

    next
}

########################################################################
# Path Group Information
########################################################################
/status=/ {

    split($0,a,"status=")
    group=a[2]

    if(group=="active")
        color=green
    else if(group=="enabled")
        color=blue
    else
        color=red

    printf "\n%sMultipath Device : %s%s\n", yellow, alias, reset
    printf "WWID             : %s\n", wwid
    printf "Path Group       : %s%s%s\n\n", color, group, reset

    printf "%-12s %-8s %-8s %-10s\n","DEVICE","MAJ:MIN","DM_STATUS","PATH_STATUS"
    printf "%-12s %-8s %-8s %-10s\n","------------","--------","--------","-----------"

    next
}

########################################################################
# Individual Paths
########################################################################
/^[[:space:]]*[|`]/ {

    disk=""
    majmin=""
    dmstat=""
    pstat=""

    for(i=1;i<=NF;i++){

        if($i ~ /^[0-9]+:[0-9]+$/)
            majmin=$i

        if($i ~ /^sd[a-z]+$/)
            disk=$i

        if($i=="active" || $i=="enabled" || $i=="failed" || $i=="faulty")
            dmstat=$i
    }

    pstat=$(NF)

    if(disk!=""){

        if(dmstat=="active" || dmstat=="enabled"){

            printf "%-12s %-8s %-8s %s%-10s%s\n",
                   disk,majmin,dmstat,green,pstat,reset

            good++
        }
        else{

            printf "%-12s %-8s %-8s %s%-10s%s\n",
                   disk,majmin,dmstat,red,pstat,reset

            bad++
        }
    }
}

END{

    total=good+bad

    print ""
    print "==============================================================="
    print "SUMMARY"
    print "==============================================================="

    printf "Good Paths   : %s%d%s\n",green,good,reset
    printf "Faulty Paths : %s%d%s\n",red,bad,reset
    printf "Total Paths  : %d\n",total

    if(bad==0)
        printf "\n%sNo Failed/Faulty Paths Found%s\n",green,reset
    else
        printf "\n%sWARNING : Failed/Faulty Paths Detected%s\n",red,reset

    print "==============================================================="
}'
