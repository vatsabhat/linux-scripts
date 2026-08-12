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
# 1. NETWORK INTERFACES & IP ADDRESSES
# ==========================================
print_section_header "INTERFACES & IP CONFIGURATION"

# Loop through all non-loopback interfaces
for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'); do
    # Get State (UP/DOWN)
    STATE=$(ip link show "$IFACE" | grep -o 'state [A-Z]*' | awk '{print $2}')
    
    # Get MAC Address
    MAC=$(ip link show "$IFACE" | awk '/link\/ether/ {print $2}')
    [ -z "$MAC" ] && MAC="N/A"
    
    # Get IPv4 Address
    IP4=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | paste -sd, -)
    [ -z "$IP4" ] && IP4="No IPv4 Assigned"

    # Get Speed (if interface is UP and physical)
    SPEED="N/A"
    if [ "$STATE" = "UP" ] && command -v ethtool >/dev/null 2>&1; then
        SPEED_VAL=$(ethtool "$IFACE" 2>/dev/null | grep "Speed:" | awk '{print $2}')
        [ -n "$SPEED_VAL" ] && SPEED="$SPEED_VAL"
    fi

    printf "$ROW_FORMAT" "Interface [$IFACE]" "Status: $STATE | Speed: $SPEED"
    printf "$ROW_FORMAT" "  ↳ MAC Address" "$MAC"
    printf "$ROW_FORMAT" "  ↳ IPv4 Address" "$IP4"
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

# Prefer ss over netstat as netstat is deprecated
if command -v ss >/dev/null 2>&1; then
    # Grab TCP listening ports, format them nicely
    while read -r proto port process; do
        printf "$ROW_FORMAT" "Listening $proto/$port" "Process: $process"
    done <<< "$(ss -tulnpH | awk '{print $1, $4, $7}' | sed 's/.*"\(.*\)".*/\1/' | awk '{print $1, substr($2, rindex($2, ":")+1), $3}' | sort -un -k2)"
else
    printf "$ROW_FORMAT" "Error" "ss command not available to check ports."
fi

echo -e "$SEPARATOR\n"
