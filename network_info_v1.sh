###############################################################################
# Network Information
###############################################################################

echo
echo "==============================================================="
echo "NETWORK INFORMATION"
echo "==============================================================="

HOSTNAME=$(hostname)

echo "Hostname : $HOSTNAME"
echo

printf "%-12s %-18s %-10s %-8s\n" \
"INTERFACE" "IP ADDRESS" "SPEED" "LINK"
printf "%-12s %-18s %-10s %-8s\n" \
"-----------" "-----------------" "---------" "------"

for IFACE in $(ls /sys/class/net | grep -v lo)
do
    IP=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

    [ -z "$IP" ] && continue

    if [ -f /sys/class/net/$IFACE/speed ]; then
        SPEED=$(cat /sys/class/net/$IFACE/speed 2>/dev/null)
        [[ "$SPEED" =~ ^[0-9]+$ ]] || SPEED="Unknown"
        [ "$SPEED" != "Unknown" ] && SPEED="${SPEED}Mb/s"
    else
        SPEED=$(ethtool "$IFACE" 2>/dev/null | awk -F': ' '/Speed/ {print $2}')
        [ -z "$SPEED" ] && SPEED="Unknown"
    fi

    LINK=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)

    printf "%-12s %-18s %-10s %-8s\n" \
        "$IFACE" "$IP" "$SPEED" "$LINK"
done

echo
###############################################################################
# Default Gateway
###############################################################################

echo "Default Gateway"
echo "---------------------------------------------------------------"

ip route | awk '/^default/ {
printf "Gateway   : %s\n",$3;
printf "Interface : %s\n",$5;
}'

echo

###############################################################################
# Routing Table
###############################################################################

echo "Routing Table"
echo "---------------------------------------------------------------"

printf "%-18s %-18s %-10s %-10s\n" \
"DESTINATION" "GATEWAY" "INTERFACE" "PROTO"

ip route | while read line
do
    DEST=$(echo "$line" | awk '{print $1}')

    GW=$(echo "$line" | awk '{
        for(i=1;i<=NF;i++)
            if($i=="via")
                print $(i+1)
    }')

    DEV=$(echo "$line" | awk '{
        for(i=1;i<=NF;i++)
            if($i=="dev")
                print $(i+1)
    }')

    PROTO=$(echo "$line" | awk '{
        for(i=1;i<=NF;i++)
            if($i=="proto")
                print $(i+1)
    }')

    [ -z "$GW" ] && GW="-"
    [ -z "$PROTO" ] && PROTO="-"

    printf "%-18s %-18s %-10s %-10s\n" \
        "$DEST" "$GW" "$DEV" "$PROTO"
done

echo "==============================================================="