#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Target port from the first script argument
NEW_PORT=$1

# ----------------------------------------------------
# 1. Validation Checks
# ----------------------------------------------------
if [ -z "$NEW_PORT" ]; then
    echo "❌ Error: Please specify a port number."
    echo "Usage: sudo $0 <new_port_number>"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run as root (or with sudo)."
    exit 1
fi

# Ensure policycoreutils-python-utils is installed for semanage
if ! command -v semanage &> /dev/null; then
    echo "📦 Installing policycoreutils-python-utils..."
    dnf install -y policycoreutils-python-utils
fi

echo "🔄 Changing SSH port to $NEW_PORT on RHEL 9..."

# ----------------------------------------------------
# 2. Configure SELinux
# ----------------------------------------------------
echo "🔐 Updating SELinux policies..."
if semanage port -l | grep -q -w "$NEW_PORT"; then
    # If port is already assigned to something else, try to modify it
    semanage port -m -t ssh_port_t -p tcp "$NEW_PORT" || true
else
    semanage port -a -t ssh_port_t -p tcp "$NEW_PORT"
fi

# ----------------------------------------------------
# 3. Configure Firewalld
# ----------------------------------------------------
echo "🔥 Opening port $NEW_PORT in firewalld..."
firewall-cmd --permanent --add-port="${NEW_PORT}/tcp"
firewall-cmd --reload

# ----------------------------------------------------
# 4. Configure SSH Drop-in File
# ----------------------------------------------------
echo "⚙️ Creating SSH drop-in configuration..."
mkdir -p /etc/ssh/sshd_config.d/
echo "Port $NEW_PORT" > /etc/ssh/sshd_config.d/10-port.conf

# ----------------------------------------------------
# 5. Test & Restart SSH
# ----------------------------------------------------
echo "🧪 Testing SSH configuration syntax..."
if sshd -t; then
    echo "🚀 Restarting SSH service..."
    systemctl restart sshd
    echo "✅ Success! SSH port changed to $NEW_PORT."
    echo "⚠️  CRITICAL: Do NOT close this terminal. Open a NEW window to test access:"
    echo "    ssh -p $NEW_PORT your_user@$(hostname -I | awk '{print $1}')"
else
    echo "❌ Error: SSH configuration test failed. Reverting changes..."
    rm -f /etc/ssh/sshd_config.d/10-port.conf
    exit 1
fi
