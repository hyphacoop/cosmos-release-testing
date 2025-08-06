#!/bin/bash

INIT='{"count":100}'
QUERY='{"get_count":{}}'
EXEC="{\"increment\": {}}"

txhash=$($CHAIN_BINARY tx wasm submit-proposal store-instantiate \
    tests/contracts/counter.wasm $INIT \
    --label "my first contract" \
    --no-admin \
    --instantiate-nobody true \
    --title "Store and instantiate CW template" \
    --summary "This proposal will store and instantiate the cw template contract" \
    --deposit 10000000$DENOM -y \
    --from $WALLET_1 \
    --chain-id $CHAIN_ID \
    --gas 20000000 --gas-prices $GAS_PRICE \
    --home $whale_home -o json | jq -r '.txhash')
echo "Submitting the store-instantiate proposal..."

sleep $(($COMMIT_TIMEOUT+2))

echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $whale_home | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json"
# $CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_2 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
# $CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_3 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))

echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

# Get contract address
echo "> list-code:"
$CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq '.'
latest_code=$($CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq -r '.code_infos[-1].code_id')
echo "> Latest code: $latest_code"
contract_address=$($CHAIN_BINARY q wasm list-contract-by-code $latest_code --home $whale_home -o json | jq -r '.contracts[-1]')
echo "> Contract address: $contract_address"
echo "COUNTER_CONTRACT_ADDRESS=$contract_address" >> $GITHUB_ENV

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $whale_home -o json | jq '.data.count')
echo "Count: $count"

if [[ "$count" == "100" ]]; then
    echo "PASS: Contract was instantiated."
else
    echo "FAIL: Contract was not instantiated."
    exit 1
fi

# Increment
txhash=$($CHAIN_BINARY tx wasm execute $contract_address '{"increment":{}}' --from $WALLET_1 --chain-id $CHAIN_ID --gas auto --gas-adjustment 5 --gas-prices $GAS_PRICE -y --home $whale_home -o json | jq -r '.txhash')
echo "Execute tx hash: $txhash"
sleep $(($COMMIT_TIMEOUT*2))
$CHAIN_BINARY q tx $txhash --home $whale_home -o json | jq '.'

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $whale_home -o json | jq '.data.count')
echo "Count: $count"
if [[ "$count" == "101" ]]; then
    echo "PASS: Contract was executed."
else
    echo "FAIL: Contract was not executed."
    exit 1
fi