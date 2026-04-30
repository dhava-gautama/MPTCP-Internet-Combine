#!/usr/bin/env bash
set -euo pipefail

echo "[clientdown] Stopping socat-bridge.service..."
sudo systemctl stop socat-bridge.service || true

echo "[clientdown] Stopping sing-box.service..."
sudo systemctl stop sing-box.service || true

echo "[clientdown] Disabling services at boot..."
sudo systemctl disable sing-box.service socat-bridge.service || true
echo "[clientdown] Removing NAT MASQUERADE on tun0 (if present)..."
while sudo iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE >/dev/null 2>&1; do
	sudo iptables -t nat -D POSTROUTING -o tun0 -j MASQUERADE >/dev/null 2>&1 || true
done
echo "[clientdown] MASQUERADE removed for tun0 (if any)."

echo "[clientdown] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[clientdown] Done."