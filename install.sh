#!/usr/bin/env bash
# Install update-airplay.sh as a command (update-airplay) and run it daily via a systemd timer.
# Usage: sudo ./install.sh              install or refresh the command and daily timer
#        sudo ./install.sh --uninstall  remove the command and timer
set -euo pipefail

SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update-airplay.sh"
BIN_LINK=/usr/local/bin/update-airplay
UNIT=/etc/systemd/system/update-airplay.service
TIMER=/etc/systemd/system/update-airplay.timer

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl disable --now update-airplay.timer 2>/dev/null || true
  rm -f "$UNIT" "$TIMER" "$BIN_LINK"
  systemctl daemon-reload
  echo "Removed update-airplay command and timer."
  exit 0
fi

# sudo sets SUDO_USER to the account that ran it; the source checkouts live in that user's home.
RUN_USER="${SUDO_USER:-root}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
SRC_DIR="$RUN_HOME/src"

ln -sf "$SCRIPT_SRC" "$BIN_LINK"

cat > "$UNIT" <<EOF
[Unit]
Description=Update and rebuild NQPTP and Shairport Sync
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=SRC_DIR=$SRC_DIR
# The checkouts are owned by $RUN_USER, so let root run git in them.
Environment=GIT_CONFIG_COUNT=1
Environment=GIT_CONFIG_KEY_0=safe.directory
Environment=GIT_CONFIG_VALUE_0=*
ExecStart=$BIN_LINK
EOF

cat > "$TIMER" <<EOF
[Unit]
Description=Daily update check for NQPTP and Shairport Sync

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now update-airplay.timer

echo "Installed. Run 'sudo update-airplay' to update now."
echo "Daily runs are scheduled by systemd; check them with: systemctl list-timers update-airplay.timer"
echo "Logs: journalctl -u update-airplay.service"
