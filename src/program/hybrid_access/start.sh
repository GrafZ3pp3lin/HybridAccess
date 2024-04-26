#!/bin/bash

ip netns exec test snabb hybrid_recombinator &
snabb hybrid_loadbalancer

wait 
echo "All done"