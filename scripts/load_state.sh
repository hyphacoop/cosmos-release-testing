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

echo "> Query accounts"
$CHAIN_BINARY keys list --output json --home ${homes[0]} | jq '.'
account_1=$($CHAIN_BINARY keys list --output json --home ${homes[0]} | jq -r '.[0].address')
account_2=$($CHAIN_BINARY keys list --output json --home ${homes[0]} | jq -r '.[1].address')

echo "> Query validators"
$CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0]'
validator_1=$($CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0].operator_address')
echo "> Bank send"
$CHAIN_BINARY tx bank send $account_1 $account_2 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $TIMEOUT_COMMIT
echo "> Staking delegate"
$CHAIN_BINARY tx staking delegate $validator_1 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $TIMEOUT_COMMIT
echo "> Gov submit-proposal"
$CHAIN_BINARY tx gov submit-proposal templates/proposal-text.json --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $TIMEOUT_COMMIT
echo "> Wasm store"
$CHAIN_BINARY tx wasm store contracts/counter.wasm --from ${monikers[0]} --gas 20000000 --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $TIMEOUT_COMMIT

$CHAIN_BINARY q gov proposals --home ${homes[0]}
$CHAIN_BINARY q staking validators --output json --home ${homes[0]} | jq -r '.validators[0]'

