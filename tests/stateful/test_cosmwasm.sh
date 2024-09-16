#!/bin/bash
set -e

INIT='{"count":100}'
QUERY='{"get_count":{}}'
EXEC="{\"increment\": {}}"

echo "[INFO]: Store contract.wasm"
$CHAIN_BINARY tx wasm store tests/gaia-v18/contract.wasm --from $WALLET_1 --chain-id $CHAIN_ID --gas 20000000 --gas-prices 0.005$DENOM --home $HOME_1 -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]:Submitting the store-instantiate proposal..."
proposal=$($CHAIN_BINARY tx wasm submit-proposal store-instantiate \
    tests/gaia-v18/contract.wasm $INIT \
    --label "my first contract" \
    --no-admin \
    --instantiate-nobody true \
    --title "Store and instantiate CW template" \
    --summary "This proposal will store and instantiate the cw template contract" \
    --deposit 1000000000$DENOM -y \
    --from $WALLET_1 \
    --chain-id $CHAIN_ID \
    --gas 20000000 --gas-prices 0.005$DENOM \
    --home $HOME_1 -o json)
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
echo "[DEBUG]: submit json output:"
echo $proposal | jq -r '.'
txhash=$(echo $proposal | jq -r .txhash)

echo "[INFO]: Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "[INFO]: Proposal ID: $proposal_id"

echo "[INFO]: Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment $GAS_ADJUSTMENT -y --home $HOME_1 -o json"
echo $vote
txhash=$($vote | jq -r .txhash)
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
$CHAIN_BINARY q tx $txhash --home $HOME_1

echo "[INFO]: Waiting for the voting period to end..."
sleep $VOTING_PERIOD
echo "[INFO]: Wait for 2 blocks"
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 2 10

echo "[INFO]: Status of proposal $proposal_id"
proposal_results=$($CHAIN_BINARY --home $HOME_1 q gov proposal $proposal_id -o json)
echo $proposal_results | jq -r

# Use code 1
# Get contract address
code_id=21
contract_address=$($CHAIN_BINARY q wasm list-contract-by-code $code_id --home $HOME_1 -o json | jq -r '.contracts[0]')
echo "[INFO]: Contract address: $contract_address"

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
echo "[INFO]: Count: $count"

if [[ "$count" == "100" ]]; then
    echo "[PASS]: Contract was instantiated."
else
    echo "[FAIL]: Contract was not instantiated."
    exit 1
fi

txhash=$($CHAIN_BINARY tx wasm execute $contract_address '{"increment":{}}' --from $WALLET_1 --chain-id $CHAIN_ID --gas auto --gas-adjustment 5 --gas-prices 0.005$DENOM -y --home $HOME_1 -o json | jq -r '.txhash')
echo "Execute tx hash: $txhash"
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
echo "Count: $count"
if [[ "$count" == "101" ]]; then
    echo "PASS: Contract was executed."
else
    echo "FAIL: Contract was not executed."
    exit 1
fi