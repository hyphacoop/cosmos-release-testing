#!/bin/bash

INIT='{"count":100}'
QUERY='{"get_count":{}}'
EXEC="{\"increment\": {}}"
txhash=$($CHAIN_BINARY tx wasm submit-proposal store-instantiate \
    tests/gaia-v18/contract.wasm $INIT \
    --label "my first contract" \
    --no-admin \
    --instantiate-nobody true \
    --title "Store and instantiate CW template" \
    --summary "This proposal will store and instantiate the cw template contract" \
    --from $WALLET_1 \
    --chain-id $CHAIN_ID \
    --gas 20000000 --gas-prices 0.005$DENOM \
    --deposit 10000000$DENOM -y \
    --home $HOME_1 -o json | jq -r '.txhash')
echo "Submitting the store-instantiate proposal..."
# echo $proposal
# txhash=$($proposal | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))

echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.logs[].events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT -y --home $HOME_1 -o json"
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $txhash --home $HOME_1

echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

# Use code 1
# Get contract address
code_id=1
contract_address=$($CHAIN_BINARY q wasm list-contract-by-code $code_id --home $HOME_1 -o json | jq -r '.contracts[0]')
echo "Contract address: $contract_address"

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
echo "Count: $count"

$CHAIN_BINARY tx wasm execute $contract_address '{"increment":{}}' --from $WALLET_1 --chain-id $CHAIN_ID --gas auto --gas-adjustment 5 --gas-prices 0.005$DENOM -y --home $HOME_1
sleep $((TIMEOUT_COMMIT*3))

# Query
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
echo "Count: $count"