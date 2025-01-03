#!/bin/bash
echo "> Creating arrays"

monikers=()
homes=()
api_ports=()
rpc_ports=()
p2p_ports=()
grpc_ports=()
pprof_ports=()
logs=()
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
    p2p_port=$p2p_prefix$i
    p2p_ports+=($p2p_port)
    grpc_port=$grpc_prefix$i
    grpc_ports+=($grpc_port)
    pprof_port=$pprof_prefix$i
    pprof_ports+=($pprof_port)
    log=$log_prefix$i
    logs+=($log)
done

home=.nodesync
rpc_port=${rpc_prefix}999
api_port=${api_prefix}999
p2p_port=${p2p_prefix}999
grpc_port=${grpc_prefix}999
pprof_port=${pprof_prefix}999
log=${log_prefix}999

echo "> Create account"
key=$($CHAIN_BINARY keys add validator --home $home --output json)
address=$(echo $key | jq -r '.address')
echo "Key add output: $key"
echo "Address: $address"

echo "> Receive funds"
$CHAIN_BINARY tx bank send $WALLET_1 $address $VAL_STAKE$DENOM --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $TIMEOUT_COMMIT
$CHAIN_BINARY q bank balances $address -o json | jq '.'