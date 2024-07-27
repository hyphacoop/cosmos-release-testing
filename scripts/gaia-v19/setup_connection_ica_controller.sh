#!/bin/bash

CHAIN_1=$1
CHAIN_2=$2
client_count=$3

hermes create client --host-chain $CHAIN_1 --reference-chain $CHAIN_2
hermes create client --reference-chain $CHAIN_1 --host-chain $CHAIN_2
hermes create connection --a-chain $CHAIN_1 --a-client 07-tendermint-$client_count --b-client 07-tendermint-0

sudo systemctl restart hermes
sleep 10
journalctl -u hermes | tail -n 10