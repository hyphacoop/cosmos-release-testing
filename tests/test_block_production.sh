#!/bin/bash 
# Check that blocks are being produced.

node_host=$1
node_port=$2
height_offset=${3:-10}

if [ $4 ]
then
    max_tests=$4
else
    max_tests=20
fi

attempt_counter=0
max_attempts=2000
echo "Wait for node to respond"
until $(curl --output /dev/null --silent --head --fail http://$node_host:$node_port)
do
    if [ ${attempt_counter} -gt ${max_attempts} ]
    then
        echo ""
        echo "Tried connecting to RPC endpoint for $attempt_counter times. Exiting."
        exit 3
    fi
    printf '.'
    attempt_counter=$(($attempt_counter+1))
    sleep 10
    free -m
done

chain_version=$(curl -s http://$node_host:$node_port/abci_info | jq -r .result.response.version)
echo $chain_version
cur_height=0
until [[ "${cur_height}" -gt 1 ]]
do
    cur_height=$(curl -s http://$node_host:$node_port/block | jq -r .result.block.header.height)
    echo $cur_height
    sleep 5
done

test_counter=0
echo "Current chain version: $chain_version"
echo "Block height: $cur_height"
height=0
stop_height=$[ $cur_height + $height_offset ]
echo "Waiting to reach block height $stop_height..."
until [ $height -ge $stop_height ]
do
    sleep 5
    if [ ${test_counter} -gt ${max_tests} ]
    then
        echo "Queried the node $test_counter times with a 5s wait between queries. A block height of $stop_height was not reached. Exiting."
        exit 2
    fi
    height=$(curl -s http://$node_host:$node_port/block | jq -r .result.block.header.height)
    if [ -z "$height" ]
    then
        height=0
    fi
    echo "Block height: $height"
    test_counter=$(($test_counter+1))
done
echo "The node is producing blocks."