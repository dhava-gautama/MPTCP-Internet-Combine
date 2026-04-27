#!/usr/bin/env bash
set -euo pipefail

echo "[serverup] Reloading systemd units..."
sudo systemctl daemon-reload

echo "[serverup] Starting sing-box.service..."
sudo systemctl start sing-box.service

echo "[serverup] Starting socat-bridge.service..."
sudo systemctl start socat-bridge.service

echo "[serverup] Enabling services at boot..."
sudo systemctl enable sing-box.service socat-bridge.service

echo "[serverup] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[serverup] Done."