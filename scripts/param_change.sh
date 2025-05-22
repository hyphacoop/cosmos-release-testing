#!/bin/bash

proposal_json=$1

proposal="$CHAIN_BINARY tx gov submit-proposal $proposal_json --from $WALLET_1 --home $HOME_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y"

echo $proposal
# response=$($proposal)
# echo $response

txhash=$($proposal | jq -r .txhash)
sleep $(( $COMMIT_TIMEOUT*2 ))

echo "Proposal hash: $txhash"
$CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.'
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.logs[].events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --home $HOME_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json"
txhash=$($vote | jq -r .txhash)
sleep $(( $COMMIT_TIMEOUT*2 ))
echo "Vote hash: $txhash"
sleep $EXPEDITED_VOTING_PERIOD