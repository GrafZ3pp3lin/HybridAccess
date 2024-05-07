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
