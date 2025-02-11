#!/bin/bash

echo "Submitting the store proposal..."
txhash=$($CHAIN_BINARY tx wasm submit-proposal wasm-store \
    tests/contracts/cw3_fixed_multisig.wasm \
    --title "Store and instantiate CW template" \
    --summary "This proposal will store the cw template contract" \
    --authority cosmos10d07y265gmmuvt4z0w9aw880jnsr700j6zn9kn \
    --deposit 10000000$DENOM -y \
    --from $WALLET_1 \
    --chain-id $CHAIN_ID \
    --gas 30000000 --gas-prices 0.005$DENOM \
    --home $HOME_1 -o json | jq -r '.txhash')
# echo $proposal
# txhash=$($proposal | jq -r .txhash)
echo "Tx hash: $txhash"
sleep $(($COMMIT_TIMEOUT+2))

# $CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.'

echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json"
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_2 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_3 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))
# $CHAIN_BINARY q tx $txhash --home $HOME_1

echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

# $CHAIN_BINARY q gov proposal 1 --home $HOME_1 -o json | jq '.'
# $CHAIN_BINARY q wasm list-code --home $HOME_1 -o json | jq '.'
# $CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 -o json --home $HOME_1 | jq '.'
# Use code 1
# Get contract address
# code_id=1
# $CHAIN_BINARY q wasm list-contract-by-code 1 --home $HOME_1 -o json | jq -r '.'
# contract_address=$($CHAIN_BINARY q wasm list-contract-by-code 1 --home $HOME_1 -o json | jq -r '.code_infos[0].')

# Instantiate
# exit 0
echo "> Instantiating contract: code 1"
$CHAIN_BINARY tx wasm instantiate 1 "$(cat tests/contracts/parameters.json)" --admin="cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl" --label=my-contract --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 -o json --home $HOME_1 | jq '.'
contract_count=$($CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 --home $HOME_1 -o json | jq -r '.contract_addresses | length')
contract_address=$($CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 --home $HOME_1 -o json | jq -r '.contract_addresses[0]')
echo "Contract count: $contract_count"
echo "Contract address: $contract_address"
echo "CONTRACT_ADDRESS=$contract_address" >> $GITHUB_ENV

echo "> Fund contract"
$CHAIN_BINARY tx bank send $WALLET_1 $contract_address 10000000$DENOM --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
sleep $(($COMMIT_TIMEOUT+2))

echo "> Execute multisig contract: propose transfer"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/propose.json)" --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $HOME_1 -o json | jq '.'

echo "> Execute multisig contract: vote on transfer proposal"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/vote.json)" --from $WALLET_2 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $HOME_1 -o json | jq '.'

echo "> Execute multisig contract: execute transfer proposal"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/execute.json)" --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $HOME_1 -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $HOME_1 -o json | jq '.'


# # Query
# count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
# echo "Count: $count"

# if [[ "$count" == "100" ]]; then
#     echo "PASS: Contract was instantiated."
# else
#     echo "FAIL: Contract was not instantiated."
#     exit 1
# fi

# txhash=$($CHAIN_BINARY tx wasm execute $contract_address '{"increment":{}}' --from $WALLET_1 --chain-id $CHAIN_ID --gas auto --gas-adjustment 5 --gas-prices 0.005$DENOM -y --home $HOME_1 -o json | jq -r '.txhash')
# echo "Execute tx hash: $txhash"
# sleep $(($COMMIT_TIMEOUT*2))
# $CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

# # Query
# count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home $HOME_1 -o json | jq '.data.count')
# echo "Count: $count"
# if [[ "$count" == "101" ]]; then
#     echo "PASS: Contract was executed."
# else
#     echo "FAIL: Contract was not executed."
#     exit 1
# fi