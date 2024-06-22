#!/bin/bash

# Calculate upgrade height
echo "Calculate upgrade height"
proposal="$CHAIN_BINARY tx gov submit-proposal templates/gaia-v18/expedited-period.json --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -o json -y"
txhash=$($proposal | jq -r .txhash)
echo "tx hash: $txhash" 

sleep $COMMIT_TIMEOUT
sleep $COMMIT_TIMEOUT
echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.logs[].events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

printf "\nVOTING\n"
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT --yes --home $HOME_1
sleep $COMMIT_TIMEOUT

# exit 0
echo "Waiting $VOTING_PERIOD seconds for param change proposal to pass..."
sleep $VOTING_PERIOD

$CHAIN_BINARY q gov params --home $HOME_1