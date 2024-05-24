#!/bin/bash

ip netns exec net2 snabb hybrid_access "/home/student/snabb/config/config-receiver-t.ini" &
snabb hybrid_access "/home/student/snabb/config/config-sender-t.ini"

wait 
echo "All done"