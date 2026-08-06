#!/bin/bash
# linux_security_audit.sh
# Simple OS & Network Security Audit (RHEL 7/8/9)

HOST=$(hostname)
TS=$(date +%Y%m%d_%H%M%S)
TXT="security_${HOST}_${TS}.txt"
HTML="security_${HOST}_${TS}.html"

PASS=0; WARN=0; FAIL=0

{
echo "Linux Security Audit"
echo "Hostname : $HOST"
echo "Date     : $(date)"
echo
printf "%-28s %-8s %-20s %-20s %-30s %s\n" "CHECK" "STATUS" "CURRENT" "EXPECTED" "CONFIG FILE" "FIX"
printf "%0.s-" {1..140}; echo
} > "$TXT"

cat > "$HTML" <<EOF
<html><head><style>
body{font-family:Arial}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #999;padding:6px;font-size:13px}
.pass{background:#c6efce}.warn{background:#ffeb9c}.fail{background:#ffc7ce}
</style></head><body>
<h2>Linux Security Audit</h2>
<p><b>Hostname:</b> $HOST<br><b>Date:</b> $(date)</p>
<table>
<tr><th>Check</th><th>Status</th><th>Current</th><th>Expected</th><th>Config File</th><th>Fix</th><th>CVE/Advisory</th></tr>
EOF

add_row(){
CHK="$1"; ST="$2"; CUR="$3"; EXP="$4"; CFG="$5"; FIX="$6"; CVE="$7"
case $ST in
PASS) CLS=pass; PASS=$((PASS+1));;
WARNING) CLS=warn; WARN=$((WARN+1));;
FAIL) CLS=fail; FAIL=$((FAIL+1));;
esac
printf "%-28s %-8s %-20s %-20s %-30s %s\n" "$CHK" "$ST" "$CUR" "$EXP" "$CFG" "$FIX" >> "$TXT"
echo "<tr class='$CLS'><td>$CHK</td><td>$ST</td><td>$CUR</td><td>$EXP</td><td>$CFG</td><td><pre>$FIX</pre></td><td>$CVE</td></tr>" >> "$HTML"
}

# SELinux
SEL=$(getenforce 2>/dev/null || echo Disabled)
[[ "$SEL" == "Enforcing" ]] && add_row "SELinux" PASS "$SEL" "Enforcing" "/etc/selinux/config" "-" "N/A" \
 || add_row "SELinux" FAIL "$SEL" "Enforcing" "/etc/selinux/config" "Set SELINUX=enforcing" "Hardening"

# Firewall
systemctl is-active firewalld >/dev/null 2>&1 && \
add_row "Firewalld" PASS Running Running "-" "-" "N/A" || \
add_row "Firewalld" WARNING Stopped Running "-" "systemctl enable --now firewalld" "N/A"

# SSH Root Login
ROOT=$(awk '/^PermitRootLogin/{print $2}' /etc/ssh/sshd_config 2>/dev/null)
[ -z "$ROOT" ] && ROOT="default"
[[ "$ROOT" == "no" ]] && add_row "SSH Root Login" PASS "$ROOT" no "/etc/ssh/sshd_config" "-" "Hardening" || \
add_row "SSH Root Login" FAIL "$ROOT" no "/etc/ssh/sshd_config" "PermitRootLogin no" "Hardening"

# Password Auth
PA=$(awk '/^PasswordAuthentication/{print $2}' /etc/ssh/sshd_config 2>/dev/null)
[ -z "$PA" ] && PA="default"
[[ "$PA" == "no" ]] && add_row "SSH Password Auth" PASS "$PA" no "/etc/ssh/sshd_config" "-" "Hardening" || \
add_row "SSH Password Auth" WARNING "$PA" no "/etc/ssh/sshd_config" "PasswordAuthentication no (if using SSH keys)" "Hardening"

# Auditd
systemctl is-active auditd >/dev/null 2>&1 && \
add_row "auditd" PASS Running Running "-" "-" "N/A" || \
add_row "auditd" WARNING Stopped Running "-" "systemctl enable --now auditd" "N/A"

# IP Forward
IPF=$(cat /proc/sys/net/ipv4/ip_forward)
[[ "$IPF" == "0" ]] && add_row "IP Forwarding" PASS Disabled Disabled "/etc/sysctl.conf" "-" "N/A" || \
add_row "IP Forwarding" WARNING Enabled Disabled "/etc/sysctl.conf" "net.ipv4.ip_forward=0" "Hardening"

# Open Ports
PORTS=$(ss -tulnH 2>/dev/null | awk '{print $5}'|awk -F: '{print $NF}'|sort -nu|xargs)
add_row "Listening Ports" WARNING "${PORTS:-None}" "Only required" "firewalld" "Review unnecessary services" "N/A"

# Security updates/CVEs
if command -v dnf >/dev/null 2>&1; then
  CVECOUNT=$(dnf -q updateinfo list cves 2>/dev/null|grep -c '^CVE')
  if [ "$CVECOUNT" -gt 0 ]; then
      add_row "Security Updates" FAIL "$CVECOUNT CVEs" "0" "RPM Packages" "dnf update --security -y" "Run: dnf updateinfo list cves"
      echo -e "\nCVE LIST\n========" >> "$TXT"
      dnf -q updateinfo list cves 2>/dev/null >> "$TXT"
  else
      add_row "Security Updates" PASS "No pending CVEs" "No pending CVEs" "-" "-" "N/A"
  fi
else
  add_row "Security Updates" WARNING "DNF unavailable" "-" "-" "-" "Unsupported"
fi

echo -e "\n\nSUMMARY\n-------" >> "$TXT"
echo "PASS=$PASS WARNING=$WARN FAIL=$FAIL" >> "$TXT"

cat >> "$HTML" <<EOF
</table>
<h3>Summary</h3>
<ul>
<li>PASS: $PASS</li>
<li>WARNING: $WARN</li>
<li>FAIL: $FAIL</li>
</ul>
</body></html>
EOF

echo "Reports generated:"
echo "  $TXT"
echo "  $HTML"
