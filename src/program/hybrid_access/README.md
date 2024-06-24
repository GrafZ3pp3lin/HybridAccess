Usage:
  snabb hybrid_access [arg]

Use --help for per-command usage.
Example:
    snabb alarms get-state --help


                vetha1 -- vetha2
              /                  \
veth0 -- veth1                    veth2 -- veth3
              \                  /
                vethb1 -- vethb2

veth0:        10.0.0.1/24
veth1:        10.0.0.2/24
vetha1:       10.0.0.11/24
vetha2#net2:  10.0.0.12/24
vethb1:       10.0.0.21/24
vethb2#net2:  10.0.0.22/24
veth2#net2:   10.0.0.31/24
veth3#net2:   10.0.0.32/24

          v2 ─────── v2
        ╱              ╲
v0 ── v1                v1 ── v0
        ╲              ╱
          v3 ─────── v3

└────┬─────┘         └────┬─────┘
    ha1                  ha2


Commands:
ping 10.0.100.11 -I 10.0.100.1
./iperf-3.17.1/src/iperf3 -c 10.0.100.11 -B 10.0.100.1 -i 1 -t 30 -O 3 -M 1448 -w 2M
./iperf-3.17.1/src/iperf3 -s -B 10.0.100.11

ip link set dev ens16 up
ip addr add 10.0.100.11/24 dev ens16
ip route add 10.0.100.1/24 dev ens16
arp -s 10.0.100.1 ca:77:e6:e0:04:0a -i ens16

ip link set dev enp2s13 up
ip addr add 10.0.100.1/24 dev enp2s13
arp -s 10.0.100.11 22:6a:af:6f:58:d2 -i enp2s13