#!/bin/bash

consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).consumer_id')
jq -r --arg consumer_id "$consumer_id" '.messages[0].consumer_id = $consumer_id' templates/proposal-update-stride.json > proposal-update.json

jq -r --arg topn "$TOPN" '.messages[0].power_shaping_parameters.top_N = $topn' proposal-update.json > proposal-topn.json
cp proposal-topn.json proposal-update.json

val1=$($CHAIN_BINARY comet show-address --home ${home_prefix}01)
val2=$($CHAIN_BINARY comet show-address --home ${home_prefix}02)
val3=$($CHAIN_BINARY comet show-address --home ${home_prefix}03)
echo "Adding $val1, $val2, $val3 to the allowlist"

jq -r --arg val1 "$val1" --arg val2 "$val2" --arg val3 "$val3" '.messages[0].power_shaping_parameters.allowlist = [$val1, $val2, $val3]' proposal-update.json > proposal-allowlist.json
cp proposal-allowlist.json proposal-update.json
jq '.' proposal-update.json

echo "> Query submitter balance before proposal:"
$CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq '.'

echo "> Submitting proposal."
tx="$CHAIN_BINARY tx gov submit-proposal proposal-update.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the proposal to go on chain
sleep $(($COMMIT_TIMEOUT+2))
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $whale_home
proposal_id=$($CHAIN_BINARY q tx $txhash --home $whale_home --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "> Query submitter balance after submitting proposal:"
$CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq '.'

echo "> Cancelling proposal."
tx="$CHAIN_BINARY tx gov cancel-proposal $proposal_id --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from $WALLET_1 --keyring-backend test --home $whale_home --chain-id $CHAIN_ID -y -o json"
txhash=$($tx | jq -r .txhash)
# Wait for the cancellation to go through
sleep $(($COMMIT_TIMEOUT+2))

echo "> Query submitter balance after cancelling proposal:"
$CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq '.'

echo "> Query proposal status:"
$CHAIN_BINARY q gov proposal $proposal_id --home $whale_home -o json | jq '.'
