#!/bin/bash

ip netns exec net2 snabb hybrid_access "/home/student/snabb/config/config-receiver.ini" &
snabb hybrid_access "/home/student/snabb/config/config-sender.ini"

wait 
echo "All done"