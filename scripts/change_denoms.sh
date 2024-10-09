#!/bin/bash

denom_hash=$1

echo "Patching template with consumer denom..."
jq -r --arg DENOMTOADD "ibc/$denom_hash" '.messages[0].denoms_to_add |= [$DENOMTOADD]' templates/proposal-change-reward-denoms-permissionless.json > proposal-denom-hash.json

echo "> Submit proposal with v50 command."
jq '.' proposal-denom-hash.json
proposal="$CHAIN_BINARY tx gov submit-proposal proposal-denom-hash.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --from $WALLET_2 --keyring-backend test --home $HOME_1  --chain-id $CHAIN_ID -y -o json"
txhash=$($proposal | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))

# Get proposal ID from txhash
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