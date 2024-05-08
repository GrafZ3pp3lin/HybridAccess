#!/bin/bash

ip netns exec net2 snabb hybrid_recombinator &
snabb hybrid_loadbalancer

wait 
echo "All done"