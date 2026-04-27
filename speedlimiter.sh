# limit speed upload
tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 10ms

#delete limit speed upload
tc qdisc del dev eth1 root

#download speed limiter
modprobe ifb
ip link add ifb0 type ifb
ip link set ifb0 up

#limit download
tc qdisc add dev eth0 handle ffff: ingress

tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
  action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 10ms

modprobe ifb
ip link add ifb1 type ifb
ip link set ifb1 up

tc qdisc add dev eth1 handle ffff: ingress
tc filter add dev eth1 parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb1

tc qdisc add dev ifb1 root tbf rate 20mbit burst 32kbit latency 10ms

#delete download speed limiter
tc qdisc del dev eth0 root
tc qdisc del dev eth0 ingress
tc qdisc del dev ifb0 root
ip link delete ifb0
tc qdisc del dev eth1 root
tc qdisc del dev eth1 ingress
tc qdisc del dev ifb1 root
ip link delete ifb1
