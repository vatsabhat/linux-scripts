#!/bin/bash
# Description: Comprehensive CIS Level 2 Linux Security Audit Script
# Includes: Metadata, Firewalls, Password Policies, Open Ports, Active User Accounts
# Outputs: Clean terminal text table & professional HTML report

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: Please run this script as root."
  exit 1
fi

# System Metrics
HOSTNAME=$(hostname)
AUDIT_DATE=$(date "+%Y-%m-%d %H:%M:%S")
TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || date +%Z)

# Output Paths
TXT_REPORT="server_cis_audit_${HOSTNAME}.txt"
HTML_REPORT="server_cis_audit_${HOSTNAME}.html"

# Initialize Data Arrays
declare -a CATS STATS DETS REMS CONF SERV

add_row() {
  CATS+=("$1"); STATS+=("$2"); DETS+=("$3"); REMS+=("$4"); CONF+=("$5"); SERV+=("$6")
}

# ==============================================================================
# AUDIT CHECKS (CIS Level 2 Focus)
# ==============================================================================

# 1. IP Forwarding
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "0" ]; then
  add_row "Network" "PASS" "IP forwarding disabled" "None" "/etc/sysctl.conf" "kernel"
else
  add_row "Network" "FAIL" "IP forwarding enabled" "Set net.ipv4.ip_forward=0" "/etc/sysctl.conf" "kernel"
fi

# 2. SSH Root Login
if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
  add_row "Access" "PASS" "SSH root login disabled" "None" "/etc/ssh/sshd_config" "sshd"
else
  add_row "Access" "FAIL" "SSH root login allowed" "Set PermitRootLogin no" "/etc/ssh/sshd_config" "sshd"
fi

# 3. System Auditing (auditd)
if systemctl is-active --quiet auditd 2>/dev/null; then
  add_row "Logging" "PASS" "auditd daemon active" "None" "/etc/audit/auditd.conf" "auditd"
else
  add_row "Logging" "FAIL" "auditd daemon inactive" "Enable and start auditd" "/etc/audit/auditd.conf" "auditd"
fi

# 4. Network Firewall Verification
FW_STATUS="FAIL" ; FW_TEXT="No active firewall found" ; FW_REM="Install & enable ufw/firewalld" ; FW_CONF="N/A" ; FW_SERV="none"
if systemctl is-active --quiet ufw 2>/dev/null; then
  FW_STATUS="PASS"; FW_TEXT="UFW firewall active"; FW_REM="None"; FW_CONF="/etc/ufw/ufw.conf"; FW_SERV="ufw"
elif systemctl is-active --quiet firewalld 2>/dev/null; then
  FW_STATUS="PASS"; FW_TEXT="Firewalld active"; FW_REM="None"; FW_CONF="/etc/firewalld/"; FW_SERV="firewalld"
elif iptables -L -n 2>/dev/null | grep -q -E "^(DROP|REJECT|ACCEPT)"; then
  FW_STATUS="PASS"; FW_TEXT="Raw iptables rules active"; FW_REM="None"; FW_CONF="/etc/sysconfig/iptables"; FW_SERV="iptables"
fi
add_row "Network" "$FW_STATUS" "$FW_TEXT" "$FW_REM" "$FW_CONF" "$FW_SERV"

# 5. Password Aging Metrics (PASS_MAX_DAYS <= 90)
MAX_DAYS=$(grep -E "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
if [ -n "$MAX_DAYS" ] && [ "$MAX_DAYS" -le 90 ]; then
  add_row "Identity" "PASS" "Max pass age is $MAX_DAYS days" "None" "/etc/login.defs" "shadow"
else
  add_row "Identity" "FAIL" "Max pass age ($MAX_DAYS) > 90" "Set PASS_MAX_DAYS <= 90" "/etc/login.defs" "shadow"
fi

# 6. Specific Open Ports Check
# Checks for common open ports (22, 80, 443, 3306, 5432, 8080)
OPEN_PORTS=$(ss -tuln | awk '{print $5}' | grep -oE '[0-9]+$' | sort -u | grep -E '^(22|80|443|3306|5432|8080)$' | tr '\n' ' ')
if [ -n "$OPEN_PORTS" ]; then
  add_row "Network" "INFO" "Active critical ports: $OPEN_PORTS" "Verify if all are required" "N/A" "network"
else
  add_row "Network" "PASS" "No risky unmapped web/db ports open" "None" "N/A" "network"
fi

# 7. Active Non-System User Accounts
# Filters out system accounts by UID threshold (typically >= 1000) and operational interactive shells
HUMAN_USERS=$(awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ {print $1}' /etc/passwd | tr '\n' ' ')
if [ -n "$HUMAN_USERS" ]; then
  add_row "Identity" "INFO" "Active human logins: $HUMAN_USERS" "Audit access privileges regularly" "/etc/passwd" "systemd"
else
  add_row "Identity" "WARN" "No interactive human accounts found" "Ensure admin fallback user exists" "/etc/passwd" "systemd"
fi

# ==============================================================================
# GENERATE CLEAN TEXT REPORT (Terminal & File)
# ==============================================================================
{
  echo "=========================================================================================================================="
  echo "                                           CIS LEVEL 2 SECURITY AUDIT REPORT                                              "
  echo "=========================================================================================================================="
  printf "%-12s : %s\n" "Host Name"  "$HOSTNAME"
  printf "%-12s : %s\n" "Audit Date" "$AUDIT_DATE"
  printf "%-12s : %s\n" "Timezone"   "$TIMEZONE"
  echo "=========================================================================================================================="
  printf "| %-10s | %-6s | %-32s | %-28s | %-12s |\n" "Category" "Status" "Details" "Remediation Steps" "Service"
  echo "--------------------------------------------------------------------------------------------------------------------------"
  for i in "${!CATS[@]}"; do
    printf "| %-10s | %-6s | %-32s | %-28s | %-12s |\n" "${CATS[$i]}" "${STATS[$i]}" "${DETS[$i]}" "${REMS[$i]}" "${SERV[$i]}"
  done
  echo "--------------------------------------------------------------------------------------------------------------------------"
} | tee "$TXT_REPORT"

# ==============================================================================
# GENERATE CLEAN HTML REPORT
# ==============================================================================
cat <<EOF > "$HTML_REPORT"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>CIS Security Audit - $HOSTNAME</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; background-color: #f8f9fa; color: #212529; }
  .container { max-width: 1300px; margin: 0 auto; background: #ffffff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
  h1 { font-size: 24px; color: #1a252f; margin-bottom: 20px; border-bottom: 2px solid #edf2f7; padding-bottom: 10px; }
  .meta-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin-bottom: 30px; background: #f1f3f5; padding: 15px; border-radius: 6px; }
  .meta-item span { display: block; font-size: 12px; color: #6c757d; font-weight: 600; text-transform: uppercase; }
  .meta-item strong { font-size: 16px; color: #495057; }
  table { width: 100%; border-collapse: collapse; margin-top: 10px; text-align: left; table-layout: fixed; }
  th { background-color: #f1f3f5; color: #495057; font-weight: 600; padding: 12px 16px; font-size: 14px; border-bottom: 2px solid #dee2e6; }
  td { padding: 14px 16px; font-size: 14px; border-bottom: 1px solid #dee2e6; vertical-align: top; word-wrap: break-word; }
  tr:hover { background-color: #f8f9fa; }
  .badge { display: inline-block; padding: 4px 8px; font-size: 11px; font-weight: 700; border-radius: 4px; text-align: center; width: 50px; }
  .PASS { background-color: #d4edda; color: #155724; }
  .FAIL { background-color: #f8d7da; color: #721c24; }
  .INFO { background-color: #e2f0fe; color: #004085; }
  .WARN { background-color: #fff3cd; color: #856404; }
  code { font-family: SFMono-Regular, Consolas, monospace; background: #e9ecef; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
</style>
</head>
<body>
<div class="container">
  <h1>CIS Level 2 Security Audit</h1>
  <div class="meta-grid">
    <div class="meta-item"><span>Hostname</span><strong>$HOSTNAME</strong></div>
    <div class="meta-item"><span>Audit Date</span><strong>$AUDIT_DATE</strong></div>
    <div class="meta-item"><span>Timezone</span><strong>$TIMEZONE</strong></div>
  </div>
  <table>
    <thead>
      <tr>
        <th style="width: 12%;">Category</th>
        <th style="width: 10%;">Status</th>
        <th style="width: 25%;">Details</th>
        <th style="width: 25%;">Remediation Steps</th>
        <th style="width: 18%;">Config File</th>
        <th style="width: 10%;">Service</th>
      </tr>
    </thead>
    <tbody>
EOF

for i in "${!CATS[@]}"; do
  cat <<ROW >> "$HTML_REPORT"
      <tr>
        <td><strong>${CATS[$i]}</strong></td>
        <td><span class="badge ${STATS[$i]}">${STATS[$i]}</span></td>
        <td>${DETS[$i]}</td>
        <td>${REMS[$i]}</td>
        <td><code>${CONF[$i]}</code></td>
        <td>${SERV[$i]}</td>
      </tr>
ROW
done

cat <<EOF >> "$HTML_REPORT"
    </tbody>
  </table>
</div>
</body>
</html>
EOF

echo -e "\n[+] Audit completed successfully."
echo "[+] TXT Table Report saved to : $TXT_REPORT"
echo "[+] HTML Table Report saved to: $HTML_REPORT"
