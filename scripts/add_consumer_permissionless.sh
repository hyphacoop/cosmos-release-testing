#!/bin/bash

echo "Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns -d '30 secs' | sed s/+00:00/Z/ | sed s/,/./) # 30 seconds in the future
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/create-consumer.json > create-spawn.json

if [ $PSS_ENABLED == true ]; then
    echo "Patching for PSS..."
    jq -r --argjson TOPN $TOPN '.power_shaping_parameters.top_N |= $TOPN' create-spawn.json > create-topn.json
    cp create-topn.json create-spawn.json
    cat create-spawn.json
fi

sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" create-spawn.json > create-$CONSUMER_CHAIN_ID.json
rm create-spawn.json

echo "Submitting proposal..."

tx="$CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

export consumer_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="consumer_creation") | .attributes[] | select(.key=="consumer_id") | .value')
echo "Consumer ID: $consumer_id"
echo "CONSUMER_ID=$consumer_id" >> $GITHUB_ENV