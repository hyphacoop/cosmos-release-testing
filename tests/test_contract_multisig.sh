#!/bin/bash
$CHAIN_BINARY q bank balances $WALLET_3 --home $whale_home -o json | jq '.'

$CHAIN_BINARY tx wasm store tests/contracts/cw3_fixed_multisig.wasm \
    --from $WALLET_1 \
    --keyring-backend test \
    --chain-id $CHAIN_ID \
    --gas 30000000 \
    --gas-prices $GAS_PRICE \
    -y \
    --home $whale_home -o json | jq '.'
# echo "Submitting the store proposal..."
# txhash=$($CHAIN_BINARY tx wasm submit-proposal wasm-store \
#     tests/contracts/cw3_fixed_multisig.wasm \
#     --title "Store and instantiate CW template" \
#     --summary "This proposal will store the cw template contract" \
#     --authority cosmos10d07y265gmmuvt4z0w9aw880jnsr700j6zn9kn \
#     --deposit 10000000$DENOM -y \
#     --from $WALLET_1 \
#     --chain-id $CHAIN_ID \
#     --gas 30000000 --gas-prices 0.005$DENOM \
#     --home $whale_home -o json | jq -r '.txhash')
# echo "Tx hash: $txhash"
# sleep $(($COMMIT_TIMEOUT+2))

# echo "Getting proposal ID from txhash..."
# proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $whale_home | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
# echo "Proposal ID: $proposal_id"

# echo "Submitting the \"yes\" vote to proposal $proposal_id..."
# $CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $whale_home -o json
# $CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_2 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $whale_home -o json
# $CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_3 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $whale_home -o json
# sleep $(($COMMIT_TIMEOUT+2))

# echo "Waiting for the voting period to end..."
# sleep $VOTING_PERIOD

echo "> List code"
$CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq -r '.'
latest_code=$($CHAIN_BINARY q wasm list-code --home $whale_home -o json | jq -r '.code_infos[-1].code_id')
echo "> Latest code: $latest_code"

# Instantiate
echo "> Instantiating contract: code id $latest_code"
$CHAIN_BINARY tx wasm instantiate $latest_code "$(cat tests/contracts/parameters.json)" --admin="cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl" --label=my-contract --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices 0.006$DENOM --gas-adjustment 4 -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))
echo "> List contracts created by $WALLET_1:"
$CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 -o json --home $whale_home | jq '.'
contract_count=$($CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 --home $whale_home -o json | jq -r '.contract_addresses | length')
contract_address=$($CHAIN_BINARY q wasm list-contracts-by-creator $WALLET_1 --home $whale_home -o json | jq -r '.contract_addresses[-1]')
echo "> Contract count: $contract_count"
echo "> Contract address: $contract_address"
echo "MULTISIG_CONTRACT_ADDRESS=$contract_address" >> $GITHUB_ENV

echo "> Fund contract"
$CHAIN_BINARY tx bank send $WALLET_1 $contract_address 10000000$DENOM --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))

echo "> Execute multisig contract: propose transfer"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/propose.json)" --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $whale_home -o json | jq '.'

echo "> Execute multisig contract: vote on transfer proposal"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/vote.json)" --from $WALLET_2 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $whale_home -o json | jq '.'

echo "> Execute multisig contract: execute transfer proposal"
$CHAIN_BINARY tx wasm execute $contract_address "$(cat tests/contracts/execute.json)" --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q wasm contract-state all $contract_address --home $whale_home -o json | jq '.'

$CHAIN_BINARY q bank balances $WALLET_3 --home $whale_home -o json | jq '.'