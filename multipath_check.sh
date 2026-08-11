#!/bin/bash
HST=$(hostname)
DT=$(date)
# Define ANSI Color Codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
CY='\033[1;35m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color
echo "======================================"
echo -e " ${CY}  hostname::$HST ${NC}"
echo -e " ${CY}  date::$DT  ${NC}"
echo "======================================"

# Check if multipath command exists and run it
if ! command -v multipath &> /dev/null; then
    echo -e "${RED}Error: 'multipath' command not found. Run as root.${NC}"
    exit 1
fi

echo -e "${CYAN}=== Multipath Disk Status Monitor ===${NC}"
printf "%-20s %-35s %-12s %-10s %-10s\n" "ALIAS" "WWID" "DEV" "PATH-STAT" "DM-STAT"
echo "--------------------------------------------------------------------------------"

# Parse multipath -ll topology output
multipath -ll | while read -r line; do
    # Check if line defines a multipath map entry (contains WWID in parentheses)
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]+\(([0-9a-fA-F]+)\) ]]; then
        current_alias="${BASH_REMATCH[1]}"
        current_wwid="${BASH_REMATCH[2]}"
    # Check if line represents an underlying path component
    elif [[ "$line" =~ [[:space:]]*([0-9]+:[0-9]+:[0-9]+:[0-9]+)[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([0-9:]+)[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
        dev_node="${BASH_REMATCH[2]}"
        path_stat="${BASH_REMATCH[4]}"
        dm_stat="${BASH_REMATCH[5]}"

        # Color-code path status
        case "$path_stat" in
            ready|active|enabled)
                p_color="$GREEN"
                ;;
            faulty|shaky)
                p_color="$YELLOW"
                ;;
            failed|offline|undef)
                p_color="$RED"
                ;;
            *)
                p_color="$NC"
                ;;
        esac

        # Color-code DM status
        case "$dm_stat" in
            active)
                d_color="$GREEN"
                ;;
            failed|faulty)
                d_color="$RED"
                ;;
            *)
                d_color="$NC"
                ;;
        esac

        # Print formatted row with colors
        printf "%-20s %-35s ${BLUE}%-12s${NC} ${p_color}%-10s${NC} ${d_color}%-10s${NC}\n" \
            "$current_alias" "$current_wwid" "$dev_node" "$path_stat" "$dm_stat"
    fi
done