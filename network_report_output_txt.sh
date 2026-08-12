#!/bin/bash

# Ensure the script is run as root for full socket/tool visibility
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to fetch complete network information."
  exit 1
fi

# Set the output text file name
OUTPUT_FILE="$(hostname)_network_report.txt"

# Clear out any existing file to start fresh
> "$OUTPUT_FILE"

# Capture dynamic system meta information
SYS_HOSTNAME=$(hostname)
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

SEPARATOR="========================================================================================================================"

# Helper function to write messages to BOTH terminal and output file seamlessly
log_output() {
    echo -e "$1"
    echo -e "$1" >> "$OUTPUT_FILE"
}

# Helper function to print tables using formatted text strings safely
log_printf() {
    local format_str="$1"
    shift
    printf "$format_str" "$@"
    printf "$format_str" "$@" >> "$OUTPUT_FILE"
}

print_section_header() {
    log_output "\n$SEPARATOR"
    log_output "  NETWORK COMPONENT: $1"
    log_output "$SEPARATOR"
}

# ==========================================
# REPORT SUMMARY HEADER
# ==========================================
log_output "$SEPARATOR"
log_output "  AUTOMATED LINUX NETWORK REPORT"
log_output "$SEPARATOR"
log_printf "%-25s | %-60s\n" "System Hostname" "$SYS_HOSTNAME"
log_printf "%-25s | %-60s\n" "Generated On" "$CURRENT_DATE"
log_output "$SEPARATOR"


# ==========================================
# 1. NETWORK INTERFACES & HARDWARE CONFIGURATION
# ==========================================
print_section_header "INTERFACES & CONFIGURATION DETAIL"

log_printf "%-15s | %-8s | %-17s | %-18s | %-6s | %-8s | %-30s\n" "Interface" "Status" "MAC Address" "IPv4 Address" "MTU" "Speed" "Type / Underlying Ports"
log_output "----------------|----------|-------------------|--------------------|--------|----------|------------------------------------------------"

for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'); do
    if [ -f "/sys/class/net/$IFACE/operstate" ]; then
        STATE=$(cat "/sys/class/net/$IFACE/operstate" | tr '[:lower:]' '[:upper:]')
    else
        STATE=$(ip link show "$IFACE" | grep -oi 'state [a-z]*' | awk '{print toupper($2)}')
    fi

    MAC=$(ip link show "$IFACE" | awk '/link\/ether/ {print $2}')
    [ -z "$MAC" ] && MAC="N/A"

    IP4=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | paste -sd, -)
    [ -z "$IP4" ] && IP4="No IP"

    MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null || echo "N/A")

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

    TYPE_INFO="Standard/Physical"
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

    log_printf "%-15s | %-8s | %-17s | %-18s | %-6s | %-8s | %-30s\n" \
        "$IFACE" "$STATE" "$MAC" "$IP4" "$MTU" "$SPEED" "$TYPE_INFO"
done


# ==========================================
# 2. ROUTING Table & GATEWAYS
# ==========================================
print_section_header "ROUTING & SYSTEM GATEWAYS"

log_printf "%-25s | %-20s | %-15s | %-40s\n" "Route Type / Target" "Gateway IP" "Outbound Dev" "Notes / Flags"
log_output "--------------------------|----------------------|-----------------|----------------------------------------"

DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -n1)
DEFAULT_INT=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -n "$DEFAULT_GW" ]; then
    log_printf "%-25s | %-20s | %-15s | %-40s\n" "Default Gateway" "$DEFAULT_GW" "$DEFAULT_INT" "Primary Outbound Path"
else
    log_printf "%-25s | %-20s | %-15s | %-40s\n" "Default Gateway" "None Configured" "N/A" "Warning: No route to outside networks"
fi

ip route | grep -v 'default' | while read -r route_line; do
    [ -z "$route_line" ] && continue

    target=$(echo "$route_line" | awk '{print $1}')

    if echo "$route_line" | grep -q 'via'; then
        gw=$(echo "$route_line" | awk -F'via ' '{print $2}' | awk '{print $1}')
        notes="Static Route"
    else
        gw="Direct Link"
        notes="Kernel Proto / Local Subnet"
    fi

    dev=$(echo "$route_line" | awk -F'dev ' '{print $2}' | awk '{print $1}')
    [ -z "$dev" ] && dev="N/A"

    log_printf "%-25s | %-20s | %-15s | %-40s\n" "$target" "$gw" "$dev" "$notes"
done


# ==========================================
# 3. DNS & RESOLUTION
# ==========================================
print_section_header "DNS & RESOLUTION"

ROW_FORMAT="%-25s | %-60s\n"

NAMESERVERS=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd, -)
log_printf "$ROW_FORMAT" "Configured DNS" "${NAMESERVERS:-None found in resolv.conf}"

SEARCH_DOM=$(grep -E '^search' /etc/resolv.conf | awk '{$1=""; print $0}' | sed 's/^ //')
log_printf "$ROW_FORMAT" "DNS Search Domains" "${SEARCH_DOM:-None configured}"

if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    CONN_STATUS="Active (Ping to 1.1.1.1 succeeded)"
else
    CONN_STATUS="No Internet / Ping Blocked"
fi
log_printf "$ROW_FORMAT" "Internet Access" "$CONN_STATUS"


# ==========================================
# 4. LISTENING PORTS & SERVICES
# ==========================================
print_section_header "LISTENING SERVICES (TCP/UDP)"

if command -v ss >/dev/null 2>&1; then
    ss -tulnpH | sort -k4 | while read -r line; do
        [ -z "$line" ] && continue

        proto=$(echo "$line" | awk '{print $1}')
        local_addr=$(echo "$line" | awk '{print $4}')

        port="${local_addr##*:}"
        process=$(echo "$line" | cut -d'"' -f2)

        if [ "$process" = "$line" ] || [ -z "$process" ]; then
            process="Unknown/No Permission"
        fi

        log_printf "$ROW_FORMAT" "Listening $proto/$port" "Process: $process"
    done
else
    log_printf "$ROW_FORMAT" "Error" "ss command not available to check ports."
fi

log_output "$SEPARATOR\n"

echo "💡 SUCCESS: Full diagnostic summary has been written to '$OUTPUT_FILE'."
