#!/bin/bash 
# Check that blocks are being produced.

gaia_host=$1
gaia_port=$2
height_offset=${3:-10}
if [ $4 ]
then
    max_tests=$4
else
    max_tests=20
fi

# Test gaia response
tests/test_node_response.sh $gaia_host $gaia_port $max_tests
# Exit if test_node_response.sh fails
if [ $? != 0 ]
then
    exit 1
fi

# Get the current gaia version and block height from the API
chain_version=$(curl -s http://$gaia_host:$gaia_port/abci_info | jq -r .result.response.version)
echo $chain_version
cur_height=0
until [[ "${cur_height}" -gt 1 ]]
do
    cur_height=$(curl -s http://$gaia_host:$gaia_port/block | jq -r .result.block.header.height)
    echo $cur_height
    sleep 5
done

# Check if gaia is producing blocks
test_counter=0
echo "Current node binary version: $chain_version"
echo "Block height: $cur_height"
height=0
stop_height=$[ $cur_height + $height_offset ]
echo "Waiting to reach block height $stop_height..."
until [ $height -ge $stop_height ]
do
    sleep 5
    if [ ${test_counter} -gt ${max_tests} ]
    then
        echo "Queried node $test_counter times with a 5s wait between queries. A block height of $stop_height was not reached. Exiting."
        exit 2
    fi
    height=$(curl -s http://$gaia_host:$gaia_port/block | jq -r .result.block.header.height)
    if [ -z "$height" ]
    then
        height=0
    fi
    echo "Block height: $height"
    test_counter=$(($test_counter+1))
done
echo "Node is producing blocks."
