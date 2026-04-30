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
echo "[clientup] Ensuring NAT MASQUERADE on tun0 (idempotent)..."
if ! sudo iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE >/dev/null 2>&1; then
	sudo iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
	echo "[clientup] MASQUERADE added for tun0."
else
	echo "[clientup] MASQUERADE already present for tun0."
fi

echo "[clientup] Current status:"
sudo systemctl --no-pager --full status sing-box.service socat-bridge.service || true

echo "[clientup] Done."