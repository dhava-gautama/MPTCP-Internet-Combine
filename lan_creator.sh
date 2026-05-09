#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: lan_creator.sh failed at line $LINENO" >&2' ERR

# Configuration (edit these before running)
interface=""   # interface yang akan jadi DHCP server (contoh: eth1)
ip="10.0.99.1"          # IP yang akan jadi gateway untuk LAN (contoh: 192.168.50.1)

# Optional tuning
netmask=24
dns1="8.8.8.8"
dns2="8.8.4.4"
lease_time="12h"

require_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: Variabel $name belum diisi. Edit variabel di bagian atas skrip." >&2
    exit 1
  fi
}

require_var "interface"
require_var "ip"

prefix="${ip%.*}"
subnet="${prefix}.0/24"
dhcp_start="${prefix}.10"
dhcp_end="${prefix}.250"

echo "[lan_creator] Configuring interface $interface with $ip/$netmask"
# add IP to interface if not present
if ! ip -4 addr show dev "$interface" | grep -qw "${ip}"; then
  sudo ip addr add "${ip}/${netmask}" dev "$interface" || true
fi
sudo ip link set dev "$interface" up

# install dnsmasq if missing
if ! command -v dnsmasq >/dev/null 2>&1; then
  echo "[lan_creator] Installing dnsmasq..."
  sudo apt-get update
  sudo apt-get install -y dnsmasq
fi

# write dnsmasq config (idempotent)
conf=/etc/dnsmasq.d/lan_creator.conf
sudo tee "$conf" >/dev/null <<EOF
interface=${interface}
bind-interfaces
listen-address=${ip}
dhcp-range=${dhcp_start},${dhcp_end},${lease_time}
dhcp-option=3,${ip}
dhcp-option=6,${dns1},${dns2}
no-resolv
domain-needed
EOF

echo "[lan_creator] Restarting dnsmasq"
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq || true

# enable ip forwarding
echo "[lan_creator] Enabling ip forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# detect external interface for NAT
ext_if="tun0" # default to tun0 for MPTCP tunnel
if [[ -z "$ext_if" ]]; then
  echo "[lan_creator] Warning: external interface could not be detected; skipping MASQUERADE."
  echo "[lan_creator] If you want NAT, set up a default route or pass ext interface manually."
else
  echo "[lan_creator] Detected external interface: $ext_if"
  # add NAT rule (idempotent) - apply to all outgoing traffic on external iface
  if ! sudo iptables -t nat -C POSTROUTING -o "$ext_if" -j MASQUERADE >/dev/null 2>&1; then
    sudo iptables -t nat -A POSTROUTING -o "$ext_if" -j MASQUERADE
    echo "[lan_creator] MASQUERADE added on $ext_if"
  else
    echo "[lan_creator] MASQUERADE already present"
  fi

  # forwarding rules
  if ! sudo iptables -C FORWARD -i "$interface" -o "$ext_if" -j ACCEPT >/dev/null 2>&1; then
    sudo iptables -A FORWARD -i "$interface" -o "$ext_if" -j ACCEPT
  fi
  if ! sudo iptables -C FORWARD -i "$ext_if" -o "$interface" -m state --state RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1; then
    sudo iptables -A FORWARD -i "$ext_if" -o "$interface" -m state --state RELATED,ESTABLISHED -j ACCEPT
  fi

  # try to persist rules
  sudo apt-get install -y iptables-persistent netfilter-persistent || true
  sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
  sudo netfilter-persistent save >/dev/null 2>&1 || true
fi

echo "[lan_creator] DHCP server started on ${interface} (${ip}/${netmask}). DHCP range: ${dhcp_start}-${dhcp_end}"
exit 0
