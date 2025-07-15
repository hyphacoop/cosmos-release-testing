#!/bin/bash
max_block_utilization=$($CHAIN_BINARY q feemarket params --home $HOME_1 -o json | jq -r '.max_block_utilization')
payload_size=$(echo "$max_block_utilization / 1000" | bc)
echo "Max block utilization: $max_block_utilization"
echo "Payload size: $payload_size"
# PAYLOAD_SIZE=50000

preload_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Pre-load price: $preload_price$DENOM"

openssl rand -hex $payload_size > payload.txt
# echo "Payload:"
# cat payload.txt
# jq --rawfile PAYLOAD payload.txt '$PAYLOAD'
echo "> Assembling text proposal."
jq --rawfile PAYLOAD payload.txt '.summary |= $PAYLOAD' templates/proposal-text.json > proposal.json
# echo "> Proposal JSON:"
# jq '.' proposal.json
echo "> Submitting proposal."
gas=$(echo "($max_block_utilization / 2) - 1000000" | bc)
txhash_1=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_1 --gas $gas --gas-prices $GAS_PRICES --home $HOME_1 -y -o json | jq -r '.txhash')
txhash_2=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_2 --gas $gas --gas-prices $GAS_PRICES --home $HOME_1 -y -o json | jq -r '.txhash')
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "> Proposal hashes:"
$CHAIN_BINARY q tx $txhash_1 --home $HOME_1 -o json | jq '.'
$CHAIN_BINARY q tx $txhash_2 --home $HOME_1 -o json | jq '.'
echo "$txhash_1"
echo "$txhash_2"

height_1=$($CHAIN_BINARY q tx $txhash_1 --home $HOME_1 -o json | jq -r '.height')
height_2=$($CHAIN_BINARY q tx $txhash_2 --home $HOME_1 -o json | jq -r '.height')

echo "> Transaction heights: $height_1, $height_2"

gas_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 --height $height_1 -o json | jq -r '.prices[0].amount')
echo "Gas price at tx height: $gas_price$DENOM"
if (( $(echo "$gas_price > $preload_price" | bc -l) )); then
    echo "PASS: Current price is greater than pre-load price."
else
    echo "FAIL: Current price is not greater than pre-load price."
    exit 1
fi
