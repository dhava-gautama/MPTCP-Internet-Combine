PUBLIC_IP ="" #IP Publik VPS
interface ="enp0s6"
Socat_Port = "8888" #to client MPTCP traffic
socat_internal_port = "8080" #to sing-box
echo "STEP 1: Disabling Reverse Path Filtering (rp_filter)"
sysctl -w net.mptcp.enabled=1
sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.rp_filter=0

echo "STEP 2: Setting MPTCP Limits"
ip mptcp limits set subflows 2 add_addr_accepted 2

echo "STEP 3: Adding MPTCP Endpoint for Signaling"
ip mptcp endpoint add $PUBLIC_IP dev $interface signal

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
sudo tee /etc/sing-box/config.json >/dev/null <<'EOF'
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

[Install]
WantedBy=multi-user.target
EOF