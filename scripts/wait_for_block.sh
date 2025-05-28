#!/bin/bash

target_height=$1

rpc_ports=()
for i in $(seq -w 001 $validator_count)
do
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
done

height=$(curl -s http://localhost:${rpc_ports[0]}/block | jq -r .result.block.header.height)
echo "Block height: $height"

echo "Waiting to reach block height $target_height..."
until [ $height -ge $target_height ]
do
    sleep $TIMEOUT_COMMIT
    height=$(curl -s http://localhost:${rpc_ports[0]}/block | jq -r .result.block.header.height)
    if [ -z "$height" ]
    then
        height=0
    fi
    echo "$height"
done