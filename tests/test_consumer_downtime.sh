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
wallets=()
for i in $(seq -w 01 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    consumer_moniker=$consumer_moniker_prefix$i
    consumer_monikers+=($consumer_moniker)
    home=$consumer_home_prefix$i
    homes+=($home)
    api_port=$consumer_api_prefix$i
    api_ports+=($api_port)
    rpc_port=$consumer_rpc_prefix$i
    rpc_ports+=($rpc_port)
    p2p_port=$consumer_p2p_prefix$i
    p2p_ports+=($p2p_port)
    grpc_port=$consumer_grpc_prefix$i
    grpc_ports+=($grpc_port)
    pprof_port=$consumer_pprof_prefix$i
    pprof_ports+=($pprof_port)
    log=$consumer_log_prefix$i
    logs+=($log)
done

echo "> Stopping the last validator's consumer node."
session=${consumer_monikers[-1]}
tmux send-keys -t $session C-c
echo "> Waiting for the downtime infraction."
sleep $(($COMMIT_TIMEOUT*$CONSUMER_DOWNTIME_WINDOW))
sleep $(($COMMIT_TIMEOUT*10))

$CHAIN_BINARY q slashing signing-infos --home $whale_home -o json | jq '.'
$CHAIN_BINARY q staking validators --home $whale_home -o json | jq '.'


