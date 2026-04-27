#!/usr/bin/env bash

VPS_IP="" #your server public IP
IP1="" #your client IP on eth0
IP2="" #your client IP on eth1
GATEWAY2="" #ether2 router gateway
interface1=""
interface2=""
socat_port="8888" #port to forward MPTCP traffic to sing-box
socat_internal_port="8081" #port sing-box listen to

set -Eeuo pipefail
trap 'echo "ERROR: Install client gagal di baris $LINENO." >&2' ERR

require_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: Kolom $name belum diisi. Isi semua kolom wajib sebelum STEP 1." >&2
    exit 1
  fi
}

require_var "VPS_IP"
require_var "IP1"
require_var "IP2"
require_var "GATEWAY2"
require_var "interface1"
require_var "interface2"
require_var "socat_port"
require_var "socat_internal_port"

echo "STEP 1: Paste WireGuard config dari server, install WireGuard, lalu start service"
sudo apt-get update
sudo apt-get install -y wireguard
sudo mkdir -p /etc/wireguard
echo "Paste config WireGuard client dari server ke /etc/wireguard/wg0.conf, lalu tekan Ctrl+D:"
sudo tee /etc/wireguard/wg0.conf >/dev/null
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0.service
sudo systemctl restart wg-quick@wg0.service

echo "STEP 2: Disabling Reverse Path Filtering (rp_filter) on eth0 and eth1..."
sudo sysctl -w net.ipv4.conf.$interface1.rp_filter=0
sudo sysctl -w net.ipv4.conf.$interface2.rp_filter=0
sudo sysctl -w net.ipv4.conf.all.rp_filter=0

echo "STEP 3: Enabling MPTCP..."
sysctl -w net.mptcp.enabled=1

echo "STEP 4: Setting MPTCP Limits..."
ip mptcp limits set subflows 2 add_addr_accepted 2

echo "STEP 5: Adding MPTCP Endpoints for Subflows..."
ip mptcp endpoint add $IP1 dev $interface1 id 1 subflow
ip mptcp endpoint add $IP2 dev $interface2 id 2 subflow

echo "STEP 6: Setting Up Custom Routes..."
ip route add $VPS_IP via $GATEWAY2 dev $interface2


echo "STEP 7: Configuring IPTables MASQUERADE..."
sudo iptables -t nat -F
sudo iptables -t nat -A POSTROUTING -o $interface1 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $interface2 -j MASQUERADE

echo "STEP 8: Installing Sing-Box..."
sudo mkdir -p /etc/apt/keyrings &&
   sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc &&
   sudo chmod a+r /etc/apt/keyrings/sagernet.asc &&
   echo '
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
' | sudo tee /etc/apt/sources.list.d/sagernet.sources &&
   sudo apt-get update &&
   sudo apt-get install sing-box # or sing-box-beta

echo "STEP 9: Configuring Sing-Box..."
sudo tee /etc/sing-box/config.json >/dev/null <<'EOF'
{
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "address": ["172.19.0.1/30"],
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": "127.0.0.1", // Ke jembatan lokal
      "server_port": $socat_internal_port,
      "method": "2022-blake3-aes-128-gcm",
      "password": "Gn1JUS14bLUHgv1cWDDp4A==",
      "multiplex": { "enabled": false } // Matikan multiplex untuk kestabilan MPTCP
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [{ "outbound": "proxy" }]
  }
}
EOF

echo "STEP 10: install socat"
sudo apt install socat -y

echo "STEP 11: Installing and Starting Services..."

# 1. Sing-box Service
sudo tee /etc/systemd/system/sing-box.service >/dev/null <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 2. Socat Bridge Service (Client Side)
sudo tee /etc/systemd/system/socat-bridge.service >/dev/null <<EOF
[Unit]
Description=Socat MPTCP Client Bridge
After=network.target

[Service]
ExecStart=/usr/bin/mptcpize run /usr/bin/socat TCP4-LISTEN:$socat_port,fork,reuseaddr TCP4:168.110.213.113:$socat_internal_port
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF


echo "SETUP DONE"