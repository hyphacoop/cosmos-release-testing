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

# Bank send
# echo "$CHAIN_BINARY tx bank send ${monikers[0]} ${monikers[1]} 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y"
# $CHAIN_BINARY tx bank send ${monikers[0]} ${monikers[1]} 1000000$DENOM --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
