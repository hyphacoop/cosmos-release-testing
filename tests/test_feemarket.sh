#!/bin/bash
max_block_utilization=$($CHAIN_BINARY q feemarket params --home $whale_home -o json | jq -r '.max_block_utilization')
payload_size=$(echo "$max_block_utilization / 1000" | bc)
echo "Max block utilization: $max_block_utilization"
echo "Payload size: $payload_size"
# PAYLOAD_SIZE=50000

preload_price=$($CHAIN_BINARY q feemarket gas-prices --home $whale_home -o json | jq -r '.prices[0].amount')
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
gas=$(echo "($max_block_utilization / 2) - 10000000" | bc)
txhash_1=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_1 --gas $gas --gas-prices $GAS_PRICE --home $whale_home -y -o json | jq -r '.txhash')
txhash_2=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_RELAYER --gas $gas --gas-prices $GAS_PRICE --home $whale_home -y -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))

echo "> Proposal hashes:"
$CHAIN_BINARY q tx $txhash_1 --home $whale_home -o json | jq '.'
$CHAIN_BINARY q tx $txhash_2 --home $whale_home -o json | jq '.'

height_1=$($CHAIN_BINARY q tx $txhash_1 --home $whale_home -o json | jq -r '.height')
height_2=$($CHAIN_BINARY q tx $txhash_2 --home $whale_home -o json | jq -r '.height')

echo "> Transaction heights: $height_1, $height_2"

gas_price=$($CHAIN_BINARY q feemarket gas-prices --home $whale_home --height $height_1 -o json | jq -r '.prices[0].amount')
echo "Gas price at tx height: $gas_price$DENOM"
if (( $(echo "$gas_price > $preload_price" | bc -l) )); then
    echo "PASS: Current price is greater than pre-load price."
else
    echo "FAIL: Current price is not greater than pre-load price."
    exit 1
fi