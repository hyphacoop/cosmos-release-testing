#!/bin/bash

proposal_json=$1

proposal="$CHAIN_BINARY tx gov submit-proposal $proposal_json --from $WALLET_1 --home $whale_home --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -o json -y"

echo $proposal
txhash=$($proposal | jq -r .txhash)
sleep $(( $COMMIT_TIMEOUT*2 ))

echo "Proposal hash: $txhash"
#$CHAIN_BINARY --output json q tx $txhash --home $whale_home | jq -r '.'
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $whale_home | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --home $whale_home --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json"
txhash=$($vote | jq -r .txhash)
sleep $(( $COMMIT_TIMEOUT*2 ))
echo "Vote hash: $txhash"
echo "> Sleeping for $EXPEDITED_VOTING_PERIOD."
sleep $EXPEDITED_VOTING_PERIOD
sleep $(( $COMMIT_TIMEOUT*2 ))
echo "> Query proposal."
$CHAIN_BINARY q gov proposal $proposal_id --home $whale_home -o json | jq '.'