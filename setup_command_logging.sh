#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Please run this script as root or with sudo." >&2
    exit 1
else
echo "🚀 Starting system-wide command logging setup on RHEL 10..."
fi
# 1. Backup existing PAM files
echo "📦 Backing up PAM configuration files..."
cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak
cp /etc/pam.d/password-auth /etc/pam.d/password-auth.bak

# 2. Add pam_tty_audit rule to system-auth if it doesn't already exist
if ! grep -q "pam_tty_audit.so" /etc/pam.d/system-auth; then
    echo "✍️ Adding TTY audit rule to /etc/pam.d/system-auth..."
    # Appends the rule to the end of the session block safely
    echo "session     required      pam_tty_audit.so enable=*" >> /etc/pam.d/system-auth
else
    echo "ℹ️ pam_tty_audit already configured in system-auth."
fi

# 3. Add pam_tty_audit rule to password-auth if it doesn't already exist
if ! grep -q "pam_tty_audit.so" /etc/pam.d/password-auth; then
    echo "✍️ Adding TTY audit rule to /etc/pam.d/password-auth..."
    echo "session     required      pam_tty_audit.so enable=*" >> /etc/pam.d/password-auth
else
    echo "ℹ️ pam_tty_audit already configured in password-auth."
fi

# 4. Enable and restart the audit daemon
echo "⚙️ Enabling and starting auditd service..."
systemctl enable auditd
# auditd can sometimes reject a standard 'restart' via systemctl for security reasons.
# If systemctl restart fails, we use service or signal, but standard systemctl works on modern RHEL.
systemctl restart auditd || service auditd restart

echo "✅ Setup complete! All user keystrokes and commands are now logged globally."
echo "💡 Note: Existing user sessions must log out and back in for changes to take effect."
echo "🔍 View logs at any time using: sudo aureport --tty"
