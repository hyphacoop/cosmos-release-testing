#!/bin/bash

echo "Calculate upgrade height"
let voting_blocks_delta=$VOTING_PERIOD/$COMMIT_TIMEOUT+5
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

