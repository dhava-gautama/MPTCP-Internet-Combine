#!/usr/bin/env bash
set -euo pipefail

echo "[clientup] Reloading systemd units..."
sudo systemctl daemon-reload

echo "[clientup] Starting sing-box.service..."
sudo systemctl start sing-box.service

echo "[clientup] Starting socat-bridge.service..."
sudo systemctl start socat-bridge.service

echo "[clientup] Enabling services at boot..."
sudo systemctl enable sing-box.service socat-bridge.service

echo "[clientup] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[clientup] Done."