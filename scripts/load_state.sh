#!/bin/bash

monikers=()
homes=()
api_ports=()
rpc_ports=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
    api_port=$api_prefix$i
    api_ports+=($api_port)
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
done

# echo "> Query accounts"
# $CHAIN_BINARY keys list --output json --home ${homes[0]} | jq '.'
account_1=$($CHAIN_BINARY keys list --output json --home ${homes[0]} | jq -r '.[0].address')
account_2=$($CHAIN_BINARY keys list --output json --home ${homes[0]} | jq -r '.[1].address')

# echo "> Query validators"
# $CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0]'
echo "> Bank send"
$CHAIN_BINARY tx bank send $account_1 $account_2 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y &> /dev/null
sleep $TIMEOUT_COMMIT
echo "> Staking delegate"
validator_1=$($CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0].operator_address')
$CHAIN_BINARY tx staking delegate $validator_1 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y &> /dev/null
sleep $TIMEOUT_COMMIT

echo "> Gov submit-proposal"
$CHAIN_BINARY tx gov submit-proposal templates/proposal-text.json --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y &> /dev/null
sleep $TIMEOUT_COMMIT

echo "> Wasm store and instantiate"
INIT='{"count":100}'
QUERY='{"get_count":{}}'
EXEC="{\"increment\": {}}"
txhash=$($CHAIN_BINARY tx wasm submit-proposal store-instantiate \
    contracts/counter.wasm $INIT \
    --label "my first contract" \
    --no-admin \
    --instantiate-nobody true \
    --title "Store and instantiate CW template" \
    --summary "This proposal will store and instantiate the cw template contract" \
    --deposit 10000000$DENOM -y \
    --from $account_1 \
    --gas 20000000 --gas-prices $GAS_PRICE \
    --home ${homes[0]} -o json | jq -r '.txhash')
sleep $TIMEOUT_COMMIT
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home ${homes[0]} | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
# echo "> Proposal ID: $proposal_id"
scripts/pass_proposal.sh $proposal_id
code_id=1
contract_address=$($CHAIN_BINARY q wasm list-contract-by-code $code_id --home ${homes[0]} -o json | jq -r '.contracts[0]')
# echo "> Wasm contract address: $contract_address"
echo "> Wasm query contract"
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home ${homes[0]} -o json | jq '.data.count')
echo "Count: $count"

echo "> Wasm execute contract"
txhash=$($CHAIN_BINARY tx wasm execute $contract_address '{"increment":{}}' --from $account_1 --chain-id $CHAIN_ID --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y --home ${homes[0]} -o json | jq -r '.txhash')
sleep $TIMEOUT_COMMIT
# $CHAIN_BINARY --output json q tx $txhash --home ${homes[0]} | jq -r '.'

echo "> Wasm query contract"
count=$($CHAIN_BINARY q wasm contract-state smart $contract_address $QUERY --home ${homes[0]} -o json | jq '.data.count')
echo "Count: $count"

# $CHAIN_BINARY q gov proposals --home ${homes[0]}
# $CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0]'
