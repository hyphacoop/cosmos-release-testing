#!/bin/bash

echo "Patching update template with consumer id..."
jq -r --arg CONSUMERID "$CONSUMER_ID" '.consumer_id |= $CONSUMERID' templates/update-consumer-infraction.json > update.json
jq '.' update.json

echo "Submitting transaction..."

tx="$CHAIN_BINARY tx provider update-consumer update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

$CHAIN_BINARY q provider list-consumer-chains -o json --home $HOME_1 | jq '.'