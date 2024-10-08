#!/bin/bash
# Launch a consumer chain

echo "Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns | sed s/+00:00/Z/ | sed s/,/./)
jq -r --arg SPAWNTIME "$spawn_time" '.spawn_time |= $SPAWNTIME' tests/patch_upgrade/proposal-add-template.json > proposal-add-spawn.json
jq -r --argjson HEIGHT "$STRIDE_REV_HEIGHT" '.initial_height.revision_height |= $HEIGHT' proposal-add-spawn.json > proposal-add-rev-height.json
jq -r --arg CHAINID "$STRIDE_CHAIN_ID" '.chain_id |= $CHAINID' proposal-add-rev-height.json > proposal-add-$STRIDE_CHAIN_ID.json

jq '.' proposal-add-$STRIDE_CHAIN_ID.json

echo "Submitting proposal..."
proposal="$CHAIN_BINARY tx gov submit-legacy-proposal consumer-addition proposal-add-$STRIDE_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_2 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo $proposal
txhash=$($proposal | jq -r .txhash)
# Wait for the proposal to go on chain
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y
sleep 2
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1

echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 3 10

$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1

echo "Collecting the CCV state..."
$CHAIN_BINARY q provider consumer-genesis $STRIDE_CHAIN_ID -o json --home $HOME_1 > ccv-pre.json
jq '.params |= . + {"soft_opt_out_threshold": "0.10"}' ccv-pre.json > ccv.json
jq '.' ccv.json

echo "Patching the consumer genesis file..."
jq -s '.[0].app_state.ccvconsumer = .[1] | .[0]' $STRIDE_HOME_1/config/genesis.json ccv.json > consumer-genesis.json
cp consumer-genesis.json $STRIDE_HOME_1/config/ccv.json

echo "Starting the consumer chain..."
screen -L -Logfile $HOME/artifact/$STRIDE_SERVICE_1-consumer.log -S $STRIDE_SERVICE_1 -d -m bash $HOME/$STRIDE_SERVICE_1.sh
# set screen to flush log to 0
screen -r $STRIDE_SERVICE_1 -p0 -X logfile flush 0
