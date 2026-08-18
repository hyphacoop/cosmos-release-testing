#!/bin/bash

INIT='{"count":100}'
QUERY='{"get_count":{}}'
EXEC="{\"increment\": {}}"

echo "> Storing counter contract..."
txhash=$($CHAIN_BINARY tx wasm store tests/contracts/counter.wasm \
    --from $WALLET_1 \
    --keyring-backend test \
    --chain-id $CHAIN_ID \
    --gas 20000000 --gas-prices $GAS_PRICE \
    -y \
    --home $whale_home -o json | jq -r '.txhash')
scripts/wait_for_tx.sh $txhash $whale_home || exit 1

echo "> list-code:"
$CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq '.'
latest_code=$($CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq -r '.code_infos[-1].code_id')
echo "> Latest code: $latest_code"

echo "> Instantiating counter contract..."
txhash=$($CHAIN_BINARY tx wasm instantiate $latest_code $INIT \
    --label "my first contract" \
    --no-admin \
    --from $WALLET_1 \
    --keyring-backend test \
    --chain-id $CHAIN_ID \
    --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT \
    -y \
    --home $whale_home -o json | jq -r '.txhash')
scripts/wait_for_tx.sh $txhash $whale_home || exit 1

# Get contract address
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