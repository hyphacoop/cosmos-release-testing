#!/bin/bash

echo "Calculate upgrade height"
voting_period_seconds=${VOTING_PERIOD::-1}
let voting_blocks_delta=$voting_period_seconds/$COMMIT_TIMEOUT+5
height=$(curl -s http://localhost:$CON1_RPC_PORT/block | jq -r .result.block.header.height)
echo "Current height: $height"
upgrade_height=$(($height+$voting_blocks_delta))
echo "Upgrade block height set to $upgrade_height."

jq --arg HEIGHT "$upgrade_height" '.messages[0].plan.height = $HEIGHT' templates/proposal-changeover.json > proposal.json
proposal="$CONSUMER_CHAIN_BINARY tx gov submit-proposal proposal.json --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$CONSUMER_DENOM --home $CONSUMER_HOME_1 -o json -y"
txhash=$($proposal | jq -r .txhash)
echo "tx hash: $txhash" 

sleep $COMMIT_TIMEOUT
echo "Getting proposal ID from txhash..."
proposal_id=$($CONSUMER_CHAIN_BINARY --output json q tx $txhash --home $CONSUMER_HOME_1 | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

printf "\nVoting...\n"
$CONSUMER_CHAIN_BINARY tx gov vote $proposal_id yes --from $MONIKER_1 --gas $GAS --gas-prices $GAS_PRICE$CONSUMER_DENOM --gas-adjustment $GAS_ADJUSTMENT --yes --home $CONSUMER_HOME_1

sleep $VOTING_PERIOD

$CONSUMER_CHAIN_BINARY q gov proposal $proposal_id --home $CONSUMER_HOME_1

revision_height=$(($upgrade_height+3))
echo "> Revision height is set to $revision_height."

echo "Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns -d '10 secs' | sed s/+00:00/Z/ | sed s/,/./) # 10 seconds in the future: not enough time to opt in
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/create-consumer.json > create-spawn.json

jq -r --argjson HEIGHT $revision_height '.initialization_parameters.initial_height.revision_height |= $HEIGHT' create-spawn.json > consumer.json
cp consumer.json create-spawn.json

sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" create-spawn.json > create-$CONSUMER_CHAIN_ID.json
rm create-spawn.json

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