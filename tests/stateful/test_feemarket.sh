#!/bin/bash
PAYLOAD_SIZE=50000

preload_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Pre-load price: $preload_price$DENOM"

openssl rand -hex $PAYLOAD_SIZE > payload.txt
echo "Payload:"
cat payload.txt
jq --rawfile PAYLOAD payload.txt '$PAYLOAD'
echo "> Assembling text proposal."
jq --rawfile PAYLOAD payload.txt '.summary |= $PAYLOAD' templates/proposal-text.json > proposal.json
echo "> Proposal JSON:"
jq '.' proposal.json
echo "> Submitting proposal."
$CHAIN_BINARY tx gov submit-proposal proposal.json --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM --home $HOME_1 -y
sleep $(($COMMIT_TIMEOUT+1))

current_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Current gas price: $current_price$DENOM"
if (( $(echo "$current_price > $preload_price" | bc -l) )); then
    echo "PASS: Current price is greater than pre-load price."
else
    echo "FAIL: Current price is not greater than pre-load price."
    exit 1
fi