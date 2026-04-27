#!/usr/bin/env bash
set -euo pipefail

echo "[clientdown] Stopping socat-bridge.service..."
sudo systemctl stop socat-bridge.service || true

echo "[clientdown] Stopping sing-box.service..."
sudo systemctl stop sing-box.service || true

echo "[clientdown] Disabling services at boot..."
sudo systemctl disable sing-box.service socat-bridge.service || true

echo "[clientdown] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[clientdown] Done."