# MPTCP Internet Combine
Combine 2 (could add more) internet links into a single faster connection exploiting MPTCP

tool used: WireGuard, sing-box and socat.

**WARNING:** experimental scripts — use at your own risk and review scripts before
running them on production systems.

**Requirements**
- Linux VPS with a public IPv4 address (Ubuntu 22 - 24), check
```bash
uname -r
```
- Kernel version should be 5.14 or later

**Quick start (Both server and client)**
1. Clone the repo and open the server installer:

```bash
git clone https://github.com/mgi24/MPTCP-Internet-Combine.git
cd MPTCP-Internet-Combine
```

**SERVER**
1. Run the server installer (on the VPS):

```bash
nano serverinstall.sh   # edit variables at top (see notes below)
sudo bash serverinstall.sh
```

2. The installer prints a WireGuard client config at the end — copy that output.

**CLIENT**
1. On the client machine, paste the WireGuard client config into `clientinstall.sh` and
	 edit other client variables if needed, then run:

```bash
sudo bash clientinstall.sh
```

**START AND STOP**

```bash
sudo bash serverup.sh           # start server services
sudo bash serverdown.sh         # stop server services
sudo bash clientup.sh           # start client
sudo bash clientdown.sh         # stop client
sudo bash flushing.sh           # cleanup (server & client)
sudo bash speedlimiter.sh start # apply tc rate limits
sudo bash speedlimiter.sh stop  # remove tc rate limits
```

Important variables (edit at top of `serverinstall.sh`)
- `PUBLIC_IP` — public IP address of the VPS (mandatory)
- `interface` — external network interface name (e.g. `eth0`) (mandatory)
- `Socat_Port` — public port for the mptcpized socat listener (default `8888`)
- `socat_internal_port` — local port for the sing-box inbound listener on the server (default `8080`); the client has its own independent value (default `8081`) for the local socat-to-sing-box bridge
- `WG_PORT` — WireGuard listen port (default `51820`)

Security and final notes
- The installer generates WireGuard keys automatically on the server and prints the
	client private key in the generated client config — move that config to the client
	securely and remove any copies you don't need.
- Review and adapt firewall rules to your environment; using MASQUERADE alters
	outbound address translation.

