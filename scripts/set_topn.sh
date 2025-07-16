#!/bin/bash

echo "> Submitting update consumer transaction to change ownership"
echo "Consumer ID: $consumer_id"
jq -r --arg consumer_id "$consumer_id" '.consumer_id |= $consumer_id' templates/update-consumer.json > update.json
cat update.json
tx="$CHAIN_BINARY tx provider update-consumer update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home -o json | jq '.'

jq -r --arg consumer_id "$consumer_id" '.messages[0].consumer_id = $consumer_id' templates/proposal-update-consumer.json > proposal-update.json
jq -r --arg topn "$TOPN" '.messages[0].power_shaping_parameters.top_N = $topn' proposal-update.json > proposal-topn.json

cat proposal-topn.json
echo "Submitting proposal to set top N > 0..."
tx="$CHAIN_BINARY tx gov submit-proposal proposal-topn.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home
proposal_id=$($CHAIN_BINARY q tx $txhash --home $whale_home --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Voting on proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json"sleep $(($COMMIT_TIMEOUT+2))
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q gov tally $proposal_id --home $whale_home

echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD
$CHAIN_BINARY q gov proposal $proposal_id --home $whale_home -o json | jq '.'

echo "Querying consumer chains..."
$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq '.'