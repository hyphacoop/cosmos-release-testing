#!/bin/bash
# Usage ./get_block_size.sh <number of blocks> <block time in seconds>
count=0
while [ $count -lt $1 ]
do
current_height=$(curl -s 127.0.0.1:$VAL1_PROM_PORT/metrics | \
grep "cometbft_consensus_height{chain_id=\"$CHAIN_ID\"}" | \
awk -F " " '{ print $2 }' | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}')

current_size=$(curl -s 127.0.0.1:$VAL1_PROM_PORT/metrics | \
grep "cometbft_consensus_block_size_bytes{chain_id=\"$CHAIN_ID\"}" | \
awk -F " " '{ print $2 }' | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * ((10 ^ $2)/1024/1024)}')
echo "Current block: $current_height size is $current_size MB"
let count=$count+1
sleep $2
done