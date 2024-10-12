#!/bin/bash

echo "Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns -d '10 secs' | sed s/+00:00/Z/ | sed s/,/./) # 10 seconds in the future: not enough time to opt in
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/create-consumer.json > create-spawn.json

sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" create-spawn.json > create-$CONSUMER_CHAIN_ID.json
rm create-spawn.json

echo "> Add denoms to allowlist."
jq -r --arg denom1 "$IBC_DENOM_1" --arg denom2 "$IBC_DENOM_2" '.allowlisted_reward_denoms.denoms |= [$denom,$denom2]' create-$CONSUMER_CHAIN_ID.json > create-denoms.json
mv create-denoms.json create-$CONSUMER_CHAIN_ID.json
jq '.' create-$CONSUMER_CHAIN_ID.json

echo "Submitting transaction..."

tx="$CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

export consumer_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="create_consumer") | .attributes[] | select(.key=="consumer_id") | .value')
echo "Consumer ID: $consumer_id"
echo "CONSUMER_ID=$consumer_id" >> $GITHUB_ENV

echo "Wait for spawn time without validators opting in..."
sleep 10
$CHAIN_BINARY q provider list-consumer-chains -o json --home $HOME_1 | jq '.'

spawn_time=$(date -u --iso-8601=ns -d '30 secs' | sed s/+00:00/Z/ | sed s/,/./) # 30 seconds in the future
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/update-spawn-time.json > update-spawn.json
jq -r --arg CONSUMERID "$consumer_id" '.consumer_id |= $CONSUMERID' update-spawn.json > update-consumer.json

echo "Moving spawn time to 30 seconds in the future..."
txhash=$($CHAIN_BINARY tx provider update-consumer update-consumer.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -o json -y | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'
$CHAIN_BINARY q provider list-consumer-chains -o json --home $HOME_1 | jq '.'