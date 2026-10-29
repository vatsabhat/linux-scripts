#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Please run this script as root or with sudo." >&2
    exit 1
fi

echo "🚀 Starting separate user sudo command logging setup..."

# 1. Define paths
SUDOERS_CONF="/etc/sudoers.d/user_command_logging"
LOG_DIR="/var/log/sudo-io"

# 2. Create the secure centralized log directory
echo "📁 Creating secure log directory at ${LOG_DIR}..."
mkdir -p "$LOG_DIR"
# Restrict permissions: read/write/execute ONLY for root
chmod 700 "$LOG_DIR"
chown root:root "$LOG_DIR"

# 3. Generate the sudo configuration file
echo "✍️ Writing configuration to ${SUDOERS_CONF}..."
cat << 'EOF' > "$SUDOERS_CONF"
# ====================================================================
# Automated Sudo Session & Input/Output Logging Configuration
# ====================================================================

# Enable complete keystroke and screen output recording
Defaults log_output
Defaults log_input

# Dynamically route logs into user-specific folders based on SSH login name
Defaults iolog_dir = /var/log/sudo-io/%{login_user}

# Automatically sequence log files chronologically
Defaults iolog_file = %{seq}
EOF

# 4. Set appropriate permissions on the new sudoers configuration file
chmod 0440 "$SUDOERS_CONF"
chown root:root "$SUDOERS_CONF"

# 5. Validate the sudoers syntax to prevent system lockouts
echo "🔍 Validating sudoers syntax configuration..."
if visudo -cf "$SUDOERS_CONF"; then
    echo "✅ Sudoers syntax check passed successfully."
else
    echo "❌ Error: Sudoers configuration syntax validation failed!" >&2
    # Clean up the broken file to prevent breaking sudo across the system
    rm -f "$SUDOERS_CONF"
    exit 1
fi

echo "🎉 Setup complete! All sudo commands are now strictly isolated per user."
echo "💡 To list logged sessions: sudo sudoreplay -l"
echo "💡 To filter by specific user: sudo sudoreplay -l user=<username>"
