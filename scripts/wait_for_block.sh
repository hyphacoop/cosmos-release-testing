#!/bin/bash

rpc_port=$1
target_height=$2

height=$(curl -s http://localhost:${rpc_port}/block | jq -r .result.block.header.height)
echo "Block height: $height"

echo "Waiting to reach block height $target_height..."
until [ $height -ge $target_height ]
do
    sleep $COMMIT_TIMEOUT
    height=$(curl -s http://localhost:${rpc_port}/block | jq -r .result.block.header.height)
    if [ -z "$height" ]
    then
        height=0
    fi
    echo "$height"
done