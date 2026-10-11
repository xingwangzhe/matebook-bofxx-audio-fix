#!/bin/bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root, for example: pkexec /usr/local/sbin/matebook-hwsp-uninstall" >&2
  exit 1
fi

systemctl disable --now matebook-hwsp-init.service 2>/dev/null || true
rm -f /etc/systemd/system/matebook-hwsp-init.service
rm -f /usr/lib/systemd/system-sleep/matebook-hwsp-resume
rm -f /usr/local/sbin/matebook-hwsp-init
rm -f /usr/local/sbin/matebook-hwsp-uninstall
systemctl daemon-reload
systemctl reset-failed matebook-hwsp-init.service 2>/dev/null || true
echo "MateBook HWSP automation removed. Current amplifier register values were left unchanged."
