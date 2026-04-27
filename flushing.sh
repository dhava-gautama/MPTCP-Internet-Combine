#!/bin/bash
echo "Cleaning up networking..."
IP_PUBLIC="" #IP Publik VPS
# 1. Clear MPTCP
ip mptcp endpoint flush
ip mptcp limits set subflows 0 add_addr_accepted 0

# 2. Clear IP Rules (kecuali rule default 0, 32766, 32767)
ip rule | grep -vE "lookup (local|main|default)" | awk -F: '{print $1}' | while read priority; do
    ip rule del priority $priority
done

# 3. Clear Custom Route Tables
ip route flush table 100 2>/dev/null

# 4. Reset IPTables
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 5. Reset Routing khusus VPS (jika ada)
ip route del $IP_PUBLIC 2>/dev/null

echo "Network flushed. System is clean."