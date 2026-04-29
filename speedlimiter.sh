#!/usr/bin/env bash
set -euo pipefail

IFACE1="eth0"
IFACE2="eth1"
RATE1="10mbit"
RATE2="20mbit"
BURST="32kbit"
LATENCY="10ms"

start() {
  tc qdisc add dev "$IFACE1" root tbf rate "$RATE1" burst "$BURST" latency "$LATENCY"

  modprobe ifb
  ip link add ifb0 type ifb
  ip link set ifb0 up
  tc qdisc add dev "$IFACE1" handle ffff: ingress
  tc filter add dev "$IFACE1" parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev ifb0
  tc qdisc add dev ifb0 root tbf rate "$RATE1" burst "$BURST" latency "$LATENCY"

  ip link add ifb1 type ifb
  ip link set ifb1 up
  tc qdisc add dev "$IFACE2" handle ffff: ingress
  tc filter add dev "$IFACE2" parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev ifb1
  tc qdisc add dev ifb1 root tbf rate "$RATE2" burst "$BURST" latency "$LATENCY"

  echo "Speed limits applied."
}

stop() {
  tc qdisc del dev "$IFACE1" root 2>/dev/null || true
  tc qdisc del dev "$IFACE1" ingress 2>/dev/null || true
  tc qdisc del dev ifb0 root 2>/dev/null || true
  ip link delete ifb0 2>/dev/null || true

  tc qdisc del dev "$IFACE2" root 2>/dev/null || true
  tc qdisc del dev "$IFACE2" ingress 2>/dev/null || true
  tc qdisc del dev ifb1 root 2>/dev/null || true
  ip link delete ifb1 2>/dev/null || true

  echo "Speed limits removed."
}

case "${1:-}" in
  start) start ;;
  stop)  stop  ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
