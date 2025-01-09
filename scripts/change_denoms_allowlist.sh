#!/bin/bash

denom_hash=$1

echo "Patching template with consumer denom..."
jq -r --arg DENOMTOADD "ibc/$denom_hash" '.allowlisted_reward_denoms.denoms |= [$DENOMTOADD]' templates/update-consumer-allowlisted-denoms.json > update-denoms.json
cp update-denoms.json update.json

jq -r --arg CONSUMERID "$CONSUMER_ID" '.consumer_id |= $CONSUMERID' update.json > update-consumer.json
cp update-consumer.json update.json

echo "> Submit update-consumer transaction."
jq '.' update.json

txhash=$($CHAIN_BINARY tx provider update-consumer update.json --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y --home $HOME_1 -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $txhash --home $HOME_1