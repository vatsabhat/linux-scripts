#!/bin/bash
# Ensure the script is run as root for full socket/tool visibility
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to fetch complete network information."
  exit 1
fi

SEPARATOR="=========================================================================================="
HEADER_FORMAT="%-25s | %-60s\n"
ROW_FORMAT="%-25s | %-60s\n"

print_section_header() {
    echo -e "\n$SEPARATOR"
    echo -e "  NETWORK COMPONENT: $1"
    echo -e "$SEPARATOR"
    printf "$HEADER_FORMAT" "Property" "Details"
    echo -e "--------------------------|--------------------------------------------------------------"
}

# ==========================================
# 1. NETWORK INTERFACES & HARDWARE CONFIGURATION
# ==========================================
print_section_header "INTERFACES & CONFIGURATION DETAIL"

# Print an explicit table header for clarity
printf "%-15s | %-10s | %-17s | %-18s | %-6s | %-12s | %-20s\n" "Interface" "Status" "MAC Address" "IPv4 Address" "MTU" "Speed" "Type/Underlying"
echo "----------------|------------|-------------------|--------------------|--------|--------------|---------------------"

for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'); do
    # Get State reliably from sysfs
    if [ -f "/sys/class/net/$IFACE/operstate" ]; then
        STATE=$(cat "/sys/class/net/$IFACE/operstate" | tr '[:lower:]' '[:upper:]')
    else
        STATE=$(ip link show "$IFACE" | grep -oi 'state [a-z]*' | awk '{print toupper($2)}')
    fi

    # Get MAC Address
    MAC=$(ip link show "$IFACE" | awk '/link\/ether/ {print $2}')
    [ -z "$MAC" ] && MAC="N/A"

    # Get IPv4 Address
    IP4=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | paste -sd, -)
    [ -z "$IP4" ] && IP4="No IP"

    # Get MTU
    MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null || echo "N/A")

    # Get Speed from sysfs
    if [ -f "/sys/class/net/$IFACE/speed" ]; then
        SPEED_VAL=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null)
        if [ -n "$SPEED_VAL" ] && [ "$SPEED_VAL" -gt 0 ] 2>/dev/null; then
            SPEED="${SPEED_VAL}M"
        else
            SPEED="N/A"
        fi
    else
        SPEED="N/A"
    fi

    # Determine Type & Underlying Ports
    TYPE_INFO="Standard"
    if [ -d "/sys/class/net/$IFACE/bridge" ]; then
        SLAVES=$(ls "/sys/class/net/$IFACE/brif/" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        TYPE_INFO="Bridge (${SLAVES:-No Ports})"
    elif [ -d "/sys/class/net/$IFACE/bonding" ]; then
        SLAVES=$(cat "/sys/class/net/$IFACE/bonding/slaves" 2>/dev/null)
        TYPE_INFO="Bond (${SLAVES:-No Slaves})"
    elif [ -f "/sys/class/net/$IFACE/master" ]; then
        MASTER_INT=$(basename "$(readlink "/sys/class/net/$IFACE/master")" 2>/dev/null)
        TYPE_INFO="Slave of $MASTER_INT"
    fi

    # Print the row aligned exactly with the table headers
    printf "%-15s | %-10s | %-17s | %-18s | %-6s | %-12s | %-20s\n" \
        "$IFACE" "$STATE" "$MAC" "$IP4" "$MTU" "$SPEED" "$TYPE_INFO"
done

# ==========================================
# 2. ROUTING & GATEWAYS
# ==========================================
print_section_header "ROUTING & GATEWAYS"

DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -n1)
DEFAULT_INT=$(ip route | grep default | awk '{print $5}' | head -n1)

printf "$ROW_FORMAT" "Default Gateway" "${DEFAULT_GW:-None configured}"
printf "$ROW_FORMAT" "Primary Outbound Dev" "${DEFAULT_INT:-None configured}"

# List static routes if any exist (excluding the default and link-local)
STATIC_ROUTES=$(ip route | grep -vE 'default|link-local|proto kernel' | awk '{print $1 " via " $3}')
if [ -n "$STATIC_ROUTES" ]; then
    printf "$ROW_FORMAT" "Static Routes" "$(echo "$STATIC_ROUTES" | tr '\n' ' ')"
else
    printf "$ROW_FORMAT" "Static Routes" "None configured"
fi


# ==========================================
# 3. DNS & RESOLUTION
# ==========================================
print_section_header "DNS & RESOLUTION"

# Extract nameservers
NAMESERVERS=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd, -)
printf "$ROW_FORMAT" "Configured DNS" "${NAMESERVERS:-None found in resolv.conf}"

# Extract search domains
SEARCH_DOM=$(grep -E '^search' /etc/resolv.conf | awk '{$1=""; print $0}' | sed 's/^ //')
printf "$ROW_FORMAT" "DNS Search Domains" "${SEARCH_DOM:-None configured}"

# Check internet connectivity quickly (1 ping to Cloudflare DNS)
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    CONN_STATUS="Active (Ping to 1.1.1.1 succeeded)"
else
    CONN_STATUS="No Internet / Ping Blocked"
fi
printf "$ROW_FORMAT" "Internet Access" "$CONN_STATUS"


# ==========================================
# 4. LISTENING PORTS & SERVICES
# ==========================================
print_section_header "LISTENING SERVICES (TCP/UDP)"

if command -v ss >/dev/null 2>&1; then
    # Works perfectly on mawk, gawk, and busybox
    ss -tulnpH | sort -k4 | while read -r line; do
        [ -z "$line" ] && continue

        # Extract protocol (tcp, udp, etc.)
        proto=$(echo "$line" | awk '{print $1}')

        # Extract the local address/port column
        local_addr=$(echo "$line" | awk '{print $4}')
        # Safely grab everything after the LAST colon (handles IPv4 and IPv6)
        port="${local_addr##*:}"

        # Extract process name between double quotes
        process=$(echo "$line" | cut -d'"' -f2)

        # If no process name or no permission, fallback cleanly
        if [ "$process" = "$line" ] || [ -z "$process" ]; then
            process="Unknown/No Permission"
        fi

        printf "$ROW_FORMAT" "Listening $proto/$port" "Process: $process"
    done
else
    printf "$ROW_FORMAT" "Error" "ss command not available to check ports."
fi

echo -e "$SEPARATOR\n"
