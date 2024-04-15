#!/bin/bash

CHAIN_1=$1
CHAIN_2=$2
client_count=$3
start_channel=$4
end_channel=$5

hermes create client --host-chain $CHAIN_1 --reference-chain $CHAIN_2
hermes create client --reference-chain $CHAIN_1 --host-chain $CHAIN_2
hermes create connection --a-chain $CHAIN_1 --a-client 07-tendermint-$client_count --b-client 07-tendermint-0

for i in {$start_channel..$end_channel};
do
    echo "creating channel-$i..."
    hermes create channel --a-chain $CHAIN_1 --a-connection connection-$client_count --a-port transfer --b-port transfer
done
sudo systemctl restart hermes
sleep 5
