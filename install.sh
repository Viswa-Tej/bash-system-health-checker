#!/usr/bin/env bash
# Installs health_check.sh as a cron job that runs every 5 minutes
# Usage: sudo bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/health_check.sh"
LOG_FILE="/var/log/health_check.log"
CRON_LINE="*/5 * * * * $INSTALL_PATH >> $LOG_FILE 2>&1"

echo "Installing health_check.sh to $INSTALL_PATH ..."
cp "$SCRIPT_DIR/health_check.sh" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "Creating log file at $LOG_FILE ..."
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

echo "Adding cron job ..."
(crontab -l 2>/dev/null | grep -v "health_check"; echo "$CRON_LINE") | crontab -

echo ""
echo "Installation complete."
echo "  Script  : $INSTALL_PATH"
echo "  Log     : $LOG_FILE"
echo "  Cron    : runs every 5 minutes"
echo ""
echo "To run manually now:"
echo "  bash $INSTALL_PATH"
echo ""
echo "To set Slack alerts:"
echo "  export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/xxx'"
echo "  Then add it to /etc/environment for persistent use."
