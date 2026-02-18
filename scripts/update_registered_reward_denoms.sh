#!/bin/bash
PROVIDER_CHANNEL=$1
provider_denom=ibc/$(echo -n transfer/$PROVIDER_CHANNEL/$CONSUMER_DENOM | shasum -a 256 | cut -d ' ' -f1 | tr '[a-z]' '[A-Z]')

echo "Patching update template with the right denom..."
jq -r --arg DENOM "$provider_denom" '.messages[0].denoms_to_add |= [$DENOM]' templates/proposal-update-registered-rewards.json > update-registered-rewards.json

cat update-registered-rewards.json
echo "Submitting proposal to update registered rewards..."
tx="$CHAIN_BINARY tx gov submit-proposal update-registered-rewards.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home
proposal_id=$($CHAIN_BINARY q tx $txhash --home $whale_home --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q gov tally $proposal_id --home $whale_home

echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD
$CHAIN_BINARY q gov proposal $proposal_id --home $whale_home -o json | jq '.'

echo "Querying consumer chains..."
$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq '.'