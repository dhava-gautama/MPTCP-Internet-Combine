#!/usr/bin/env bash

PUBLIC_IP="" # IP Publik VPS
interface=""
Socat_Port="8888" # to client MPTCP traffic
socat_internal_port="8080" # to sing-box


set -Eeuo pipefail
trap 'echo "ERROR: Install server gagal di baris $LINENO." >&2' ERR

require_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: Kolom $name belum diisi. Isi semua kolom wajib sebelum STEP 1." >&2
    exit 1
  fi
}

require_var "PUBLIC_IP"
require_var "interface"
require_var "Socat_Port"
require_var "socat_internal_port"


echo "STEP 1: Disabling Reverse Path Filtering (rp_filter)"
sudo sysctl -w net.mptcp.enabled=1
sudo sysctl -w net.mptcp.pm_type=0
if [[ -e /proc/sys/net/mptcp/checksum_enabled ]]; then
  sudo sysctl -w net.mptcp.checksum_enabled=1
fi
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.$interface.rp_filter=0



echo "STEP 1.5: Installing MPTCPize"
sudo apt-get update
sudo mkdir -p /etc/wireguard
sudo apt install mptcpize -y


echo "STEP 2: Setting MPTCP Limits"
sudo ip mptcp endpoint flush
sudo ip mptcp limits set subflows 4 add_addr_accepted 4

echo "STEP 3: Adding MPTCP Endpoint for Signaling"
sudo ip mptcp endpoint add $PUBLIC_IP dev $interface id 1 signal

echo "STEP 4: Installing Sing-Box"

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

echo "STEP 5: Configuring Sing-Box"
sudo tee /etc/sing-box/config.json >/dev/null <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "127.0.0.1",
      "listen_port": $socat_internal_port,
      "network": "tcp",
      "method": "2022-blake3-aes-128-gcm",
      "password": "Gn1JUS14bLUHgv1cWDDp4A=="
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF
echo "STEP 7: Install Socat"
sudo apt install socat -y

echo "STEP 8: Installing and Starting Services..."

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

# 2. Socat Bridge Service (Server Side)
sudo tee /etc/systemd/system/socat-bridge.service >/dev/null <<EOF
[Unit]
Description=Socat MPTCP Server Bridge
After=network.target

[Service]
ExecStart=/usr/bin/mptcpize run /usr/bin/socat TCP4-LISTEN:$Socat_Port,fork,reuseaddr TCP4:127.0.0.1:$socat_internal_port
Restart=always
RestartSec=5s
SuccessExitStatus=143
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

echo "STEP 9: Enabling IP Forwarding and Setting up iptables MASQUERADE"
# Ensure iptables and persistence tools are installed (non-interactive)
sudo apt-get update
sudo apt-get install -y iptables iptables-persistent netfilter-persistent || true

# NAT ke interface eksternal (hanya tambah jika belum ada)
if ! sudo iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE
fi

sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save || true
fi