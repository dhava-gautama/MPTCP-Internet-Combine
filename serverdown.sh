#!/usr/bin/env bash
set -euo pipefail

echo "[serverdown] Stopping socat-bridge.service..."
sudo systemctl stop socat-bridge.service || true

echo "[serverdown] Stopping sing-box.service..."
sudo systemctl stop sing-box.service || true

echo "[serverdown] Disabling services at boot..."
sudo systemctl disable sing-box.service socat-bridge.service || true

echo "[serverdown] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[serverdown] Done."