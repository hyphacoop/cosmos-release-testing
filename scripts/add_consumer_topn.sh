#!/bin/bash

echo "Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns -d '60 secs' | sed s/+00:00/Z/ | sed s/,/./) # 30 seconds in the future
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/create-consumer.json > create-spawn.json

# if [ $PSS_ENABLED == true ]; then
#     echo "Patching for PSS..."
#     jq -r --argjson TOPN $TOPN '.power_shaping_parameters.top_N |= $TOPN' create-spawn.json > create-topn.json
#     cp create-topn.json create-spawn.json
#     cat create-spawn.json
# fi

sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" create-spawn.json > create-$CONSUMER_CHAIN_ID.json
rm create-spawn.json

echo "Submitting create consumer transaction..."

tx="$CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

export consumer_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="consumer_creation") | .attributes[] | select(.key=="consumer_id") | .value')
echo "CONSUMER_ID=$consumer_id" >> $GITHUB_ENV
echo "Consumer ID: $consumer_id"
echo "Consumer ID: $CONSUMER_ID"

echo "Submitting update consumer transaction to change ownership..."

jq -r --arg consumer_id "$CONSUMER_ID" '.consumer_id |= $consumer_id' templates/update-consumer.json > update.json
cat update.json
tx="$CHAIN_BINARY tx provider update-consumer update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

jq -r --arg consumer_id "$CONSUMER_ID" '.messages[0].consumer_id = $consumer_id' templates/proposal-update-consumer.json > proposal-update.json
jq -r --arg topn "$TOPN" '.messages[0].power_shaping_parameters.top_N = $topn' proposal-update.json > proposal-topn.json

echo "Submitting proposal to set top N > 0..."
tx="$CHAIN_BINARY tx gov submit-proposal proposal-topn.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -y
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1

echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD
$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1 -o json | jq '.'

echo "Querying consumer chains..."
$CHAIN_BINARY q provider list-consumer-chains --home $HOME_1 -o json | jq '.'