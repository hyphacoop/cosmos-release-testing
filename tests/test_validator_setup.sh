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

echo "> Creating account"
$CHAIN_BINARY keys add validator --home $home -o json | jq '.'
