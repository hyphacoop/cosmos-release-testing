#!/bin/bash

echo "> Submitting update consumer transaction to change ownership"

$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).consumer_id'
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).consumer_id')
echo "Consumer ID: $consumer_id"
jq -r --arg consumer_id "$consumer_id" '.consumer_id |= $consumer_id' templates/update-consumer.json > update.json
cat update.json
tx="$CHAIN_BINARY tx provider update-consumer update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home -o json | jq '.'
