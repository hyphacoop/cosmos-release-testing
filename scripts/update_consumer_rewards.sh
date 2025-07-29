#!/bin/bash
PROVIDER_CHANNEL=$1

echo "Patching update template with consumer id..."
jq -r --arg CONSUMERID "$CONSUMER_ID" '.consumer_id |= $CONSUMERID' templates/update-consumer.json > update.json

echo "> Delete new_owner_address"
jq 'del(.new_owner_address)' update.json > update-consumer.json
cp update-consumer.json update.json

echo "> Set denom allowlist"
provider_denom=ibc/$(echo -n transfer/$PROVIDER_CHANNEL/$CONSUMER_DENOM | shasum -a 256 | cut -d ' ' -f1 | tr '[a-z]' '[A-Z]')
jq --arg denom "$provider_denom" '.allowlisted_reward_denoms |= { "denoms":[$denom] }' update.json > update-denom.json
cp update-denom.json update.json

jq '.' update.json

echo "Submitting transaction..."

tx="$CHAIN_BINARY tx provider update-consumer update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home -o json | jq '.'

$CHAIN_BINARY q provider list-consumer-chains -o json --home $whale_home | jq '.'