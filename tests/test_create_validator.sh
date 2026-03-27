#!/bin/bash
# Only needs a node_home variable to function, so we can reuse the state sync node for this test

# Create new key in state sync node's keyring
$CHAIN_BINARY keys add validator --keyring-backend test --home $node_home > /dev/null
# Get the new validator's wallet address
wallet=$($CHAIN_BINARY keys list --output json --home $node_home | jq -r --arg name "validator" '.[] | select(.name==$name).address')
echo "> Wallet: $wallet"
# Get the new validator's operator address
operator=$($CHAIN_BINARY debug bech32-convert --prefix cosmosvaloper $wallet)
echo "> Operator: $operator"

echo "> Funding the new validator's wallet from the whale account"
$CHAIN_BINARY tx bank send $WALLET_1 $wallet ${VAL_WHALE}$DENOM --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y
sleep $((COMMIT_TIMEOUT*2))

# Create a new validator with the new key
pubkey=$($CHAIN_BINARY comet show-validator --home $node_home)
echo "> Pubkey: $pubkey"
valcons=$($CHAIN_BINARY comet show-address --home $node_home)
echo "> Valcons: $valcons"

# Modify create-validator template
jq --arg pubkey "$pubkey" '.pubkey = $pubkey' templates/create-validator.json > create-validator.json
jq --arg amount "${VAL_AMOUNT}${DENOM}" '.amount = $amount' create-validator.json > create-validator-amount.json

echo "> Create validator JSON:"
jq '.' create-validator-amount.json

echo "> Submitting create-validator transaction"
txhash=$($CHAIN_BINARY tx staking create-validator create-validator-amount.json --from validator --home $node_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
echo "> Txhash: $txhash"
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking create-validator transaction"
code=$($CHAIN_BINARY q tx $txhash -o json --home $node_home | jq '.code')
if [ $code -ne 0 ]; then
    echo "Create-validator tx was unsuccessful."
    $CHAIN_BINARY q tx $txhash -o json --home $node_home | jq '.'
    exit 1
fi

echo "> Waiting for the validator to be bonded"
sleep $((COMMIT_TIMEOUT*2))

echo "> Verifying validator is bonded"
status=$($CHAIN_BINARY q staking validators --home $node_home -o json | jq -r --arg addr "$operator" '.validators[] | select(.operator_address==$addr).status')
if [[ "$status" == "BOND_STATUS_BONDED" ]]; then
    echo "> PASS: Validator is bonded."
else
    echo "> FAIL: Validator is not bonded."
    exit 1
fi

$CHAIN_BINARY q comet-validator-set --home $node_home -o json | jq '.'
echo "> Verifying validator is in the validator set"
valset=$($CHAIN_BINARY q comet-validator-set --home $node_home -o json | jq -r --arg addr "$valcons" '.validators[] | select(.address==$addr)')
if [[ -n "$valset" ]]; then
    echo "> PASS: Validator is in the validator set."
else
    echo "> FAIL: Validator is not in the validator set."
    exit 1
fi

