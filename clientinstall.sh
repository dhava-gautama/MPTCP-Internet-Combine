#!/usr/bin/env bash

VPS_IP="" #your server public IP
IP2="" #your client IP on eth1
interface1=""
interface2=""
socat_port="8888" #port to forward MPTCP traffic to sing-box
socat_internal_port="8081" #port sing-box listen to
keepalive_port="8010" #use whatever port not important


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
require_var "IP2"
require_var "interface1"
require_var "interface2"
require_var "socat_port"
require_var "socat_internal_port"


echo "STEP 1: Installing MPTCPize"
sudo apt-get update
sudo apt install mptcpize -y

echo "STEP 2: Disabling Reverse Path Filtering (rp_filter) on eth0 and eth1..."
sudo sysctl -w net.ipv4.conf.$interface1.rp_filter=0
sudo sysctl -w net.ipv4.conf.$interface2.rp_filter=0
sudo sysctl -w net.ipv4.conf.all.rp_filter=0

echo "STEP 3: Enabling MPTCP..."
sudo sysctl -w net.mptcp.enabled=1
sudo sysctl -w net.mptcp.pm_type=0
if [[ -e /proc/sys/net/mptcp/checksum_enabled ]]; then
  sudo sysctl -w net.mptcp.checksum_enabled=1
fi

echo "STEP 4: Disabling IPv6..."
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

echo "STEP 5: Setting MPTCP Limits and Endpoints..."
sudo ip mptcp endpoint flush
sudo ip mptcp limits set subflows 4 add_addr_accepted 4
sudo ip mptcp endpoint add "$IP2" dev "$interface2" id 2 subflow


echo "STEP 6: Configuring IPTables MASQUERADE..."
sudo apt-get install -y iptables-persistent netfilter-persistent || true
if ! sudo iptables -t nat -C POSTROUTING -o "$interface1" -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -o "$interface1" -j MASQUERADE
fi
if ! sudo iptables -t nat -C POSTROUTING -o "$interface2" -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -o "$interface2" -j MASQUERADE
fi
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save || true
fi

echo "STEP 7: Installing Sing-Box..."
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

echo "STEP 8: Add IP Rule for VPS tunneling exception"
# add ip rule idempotently so script won't fail if rule exists
if ! ip rule show | grep -q "to $VPS_IP"; then
  sudo ip rule add to "$VPS_IP" lookup main pref 8999
fi

  echo "STEP 9: Configuring Sing-Box..."
sudo tee /etc/sing-box/config.json >/dev/null <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "google-dns",
        "type": "tcp",
        "server": "8.8.8.8",
        "server_port": 53,
        "detour": "proxy"
      }
    ],
    "rules": [
      {
        "action": "route",
        "server": "google-dns"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false,
      "stack": "system"
      // "sniff" sudah dihapus dari sini, pindah ke route rules
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": "127.0.0.1",
      "server_port": $socat_internal_port,
      "method": "2022-blake3-aes-128-gcm",
      "password": "Gn1JUS14bLUHgv1cWDDp4A==",
      "udp_over_tcp": true,
      "multiplex": {
        "enabled": false
      }
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [
      {
        "action": "sniff",
        "timeout": "1s"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "outbound": "proxy"
      }
    ]
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
ExecStart=/usr/bin/mptcpize run /usr/bin/socat TCP4-LISTEN:$socat_internal_port,fork,reuseaddr TCP4:$VPS_IP:$socat_port
Restart=always
RestartSec=5s
SuccessExitStatus=143
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

echo "STEP 12: Installing TCP keepalive service..."
sudo apt-get install -y curl
sudo tee /etc/systemd/system/tcp-keepalive.service >/dev/null <<EOF
[Unit]
Description=TCP keepalive (curl)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/bash -lc 'while true; do /usr/bin/curl -s --max-time 2 http://$VPS_IP:$keepalive_port >/dev/null; sleep 5; done'
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now tcp-keepalive.service


echo "SETUP DONE"
