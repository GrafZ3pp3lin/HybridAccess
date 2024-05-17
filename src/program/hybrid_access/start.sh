#!/bin/bash

ip netns exec net2 snabb hybrid_access "/home/student/snabb/src/program/hybrid_access/config2.ini" &
snabb hybrid_access "/home/student/snabb/src/program/hybrid_access/config.ini"

wait 
echo "All done"