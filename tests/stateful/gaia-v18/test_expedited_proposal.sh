#!/bin/bash

# Calculate upgrade height
echo "Calculate height for mock v100 upgrade expedited proposal"
let voting_blocks_delta=15/$COMMIT_TIMEOUT+5
height=$(curl -s http://localhost:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
echo "Current height: $height"
upgrade_height=$(($height+1000))
echo "Upgrade block height set to $upgrade_height."

jq --arg HEIGHT "$upgrade_height" '.messages[0].plan.height = $HEIGHT' templates/gaia-v18/proposal-upgrade-v100.json > proposal.json
proposal="$CHAIN_BINARY tx gov submit-proposal proposal.json --from $MONIKER_1 --gas auto --gas-adjustment 2 --gas-prices 0.005$DENOM --home $HOME_1 -o json -y"
txhash=$($proposal | jq -r .txhash)
echo "tx hash: $txhash" 

sleep $COMMIT_TIMEOUT
sleep $COMMIT_TIMEOUT
echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

printf "\nVOTING\n"
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --gas auto --gas-prices 0.005$DENOM --gas-adjustment 3 --yes --home $HOME_1
echo "Sleeping for $EXPEDITED_PERIOD..."
sleep $EXPEDITED_PERIOD
$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1 -o json | jq '.'
status=$($CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1 -o json | jq -r '.status')
echo "Status: $status"
if [[ "$status" == "PROPOSAL_STATUS_PASSED" ]]; then
    echo "PASS: Expedited proposal passed."
else
    echo "FAIL: Expedited proposal did not pass."
    exit 1
fi

upgrade_name=$($CHAIN_BINARY q upgrade plan --home $HOME_1 -o json | jq -r '.name')
echo "Upgrade plan name: $upgrade_name"
if [[ "$upgrade_name" == "v19" ]]; then
    echo "PASS: Upgrade plan is set."
else
    echo "FAIL: Upgrade plan is not set."
    exit 1
fi