#!/bin/bash
PAYLOAD_SIZE=40000

preload_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Pre-load price: $preload_price$DENOM"

openssl rand -hex $PAYLOAD_SIZE > payload.txt
echo "Payload:"
cat payload.txt
jq --rawfile PAYLOAD payload.txt '$PAYLOAD'
echo "> Assembling text proposal."
jq --rawfile PAYLOAD payload.txt '.summary |= $PAYLOAD' templates/proposal-text.json > proposal.json
# echo "> Proposal JSON:"
# jq '.' proposal.json
echo "> Submitting proposal."
txhash_1=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices 0.1$DENOM --home $HOME_1 -y -o json | jq -r '.txhash')
txhash_2=$($CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_2 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices 0.1$DENOM --home $HOME_1 -y -o json | jq -r '.txhash')
# wait for block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "> Proposal hashes:"
height_1=$($CHAIN_BINARY q tx $txhash_1 --home $HOME_1 -o json | jq -r '.height')
height_2=$($CHAIN_BINARY q tx $txhash_2 --home $HOME_1 -o json | jq -r '.height')

echo "> Height for tx 1: $height_1"
echo "> Base gas price at proposal height:"
$CHAIN_BINARY q feemarket state --home $HOME_1 --height $height_1 -o json | jq -r '.base_gas_price'
echo "> Base gas price at proposal height+1:"
$CHAIN_BINARY q feemarket state --home $HOME_1 --height $(($height_1+1)) -o json | jq -r '.base_gas_price'


current_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Current gas price: $current_price$DENOM"
if (( $(echo "$current_price > $preload_price" | bc -l) )); then
    echo "PASS: Current price is greater than pre-load price."
else
    echo "FAIL: Current price is not greater than pre-load price."
    exit 1
fi