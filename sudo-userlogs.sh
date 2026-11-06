#!/bin/bash
# Enterprise User Command Logging & Logrotate Deployer for RHEL 10

# 1. Create the dedicated log directory with secure permissions
LOG_DIR="/var/log/user_logs"
mkdir -p "$LOG_DIR"
chmod 733 "$LOG_DIR"
chmod +t "$LOG_DIR" # Set sticky bit so users cannot delete each other's logs

# 2. Append the logging mechanism to /etc/profile
cat << 'EOF' > /etc/profile.d/user_command_audit.sh
# Multi-user custom command logger
if [ -n "$BASH_VERSION" ]; then
    declare -r USER_LOG_FILE="/var/log/user_logs/user-${USER}.log"
    
    # Initialize file safely if it doesn't exist
    if [ ! -f "$USER_LOG_FILE" ]; then
        touch "$USER_LOG_FILE" 2>/dev/null
        chmod 600 "$USER_LOG_FILE" 2>/dev/null
    fi

    # Read-only function to intercept and log commands securely
    log_user_command() {
        local LAST_CMD
        LAST_CMD=$(history 1 | sed -e 's/^[ ]*[0-9]*[ ]*//')
        
        # Avoid logging empty lines
        if [ -n "$LAST_CMD" ]; then
            printf '[%s] FROM=%s WORKDIR=%s CMD="%s"\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "${SSH_CLIENT%% *:-local}" \
                "$PWD" \
                "$LAST_CMD" >> "$USER_LOG_FILE" 2>/dev/null
        fi
    }
    
    # Trap each executed command
    trap 'log_user_command' DEBUG
fi
EOF

chmod 644 /etc/profile.d/user_command_audit.sh

# 3. Configure logrotate for weekly rotation with 4 weeks retention
cat << 'EOF' > /etc/logrotate.d/user-activity
/var/log/user_logs/user-*.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    create 0600 root root
    sharedscripts
}
EOF

chmod 644 /etc/logrotate.d/user-activity

# 4. Verify logrotate configuration syntax
logrotate -d /etc/logrotate.d/user-activity >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Deployment successful. Weekly log rotation and tracking active."
else
    echo "Warning: Logrotate configuration validation failed."
fi
