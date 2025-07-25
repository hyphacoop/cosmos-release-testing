#!/bin/bash
set -e

# usage:
# ./set_voting_period.sh path/to/prop.json

# get prop file from arg
prop_file=$1

# Change Voting Period
echo "Setting Voting Period"
proposal="$CHAIN_BINARY tx gov submit-proposal $prop_file --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo $proposal
gaiadout=$($proposal)
echo "gaiad output:"
echo "$gaiadout"

txhash=$(echo "$gaiadout" | jq -r .txhash)
# Wait for the proposal to go on chain
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1 --output json
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y
$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1

echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD
sleep 24

$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1
echo "$CHAIN_BINARY q gov params --home $HOME_1"
$CHAIN_BINARY q gov params --home $HOME_1
