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

echo "> Finding validator with BOND_STATUS_BONDED status."
valoper=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r '[.validators[] | select((.status=="BOND_STATUS_BONDED") and (.description.moniker!="val_01"))][0].operator_address')
echo "> Valoper: $valoper"
$CHAIN_BINARY q staking validator $valoper --home $whale_home
moniker=$($CHAIN_BINARY q staking validator $valoper --home $whale_home -o json | jq -r '.validator.description.moniker')
echo "> Moniker: $moniker"

# Jailing
echo "> Stopping the last validator's consumer node."
tmux send-keys -t $moniker C-c
sleep 2
echo "> Waiting for the downtime infraction."
sleep $(($COMMIT_TIMEOUT*$CONSUMER_DOWNTIME_WINDOW))
sleep $(($COMMIT_TIMEOUT*10))

echo "> Consumer chain valset:"
$CONSUMER_CHAIN_BINARY q tendermint-validator-set --home $consumer_whale_home -o json | jq '.'
echo "> Consumer chain slashing:"
$CONSUMER_CHAIN_BINARY q slashing signing-infos --home $consumer_whale_home -o json | jq '.'
echo "> Consumer signatures:"
curl -s http://localhost:${consumer_whale_rpc}/block | jq '.result.block.last_commit.signatures'

echo "> Provider chain valset:"
$CHAIN_BINARY q comet-validator-set --home $whale_home -o json | jq '.'
echo "> Provider chain validators:"
$CHAIN_BINARY q staking validators --home $whale_home -o json | jq '.'
echo "> Provider chain slashing:"
$CHAIN_BINARY q slashing signing-infos --home $whale_home -o json | jq '.'

$CHAIN_BINARY q staking validator $valoper --home $whale_home -o json | jq '.'
status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).status')
echo "> Status: $status"
if [[ "$status" == "BOND_STATUS_BONDED" ]]; then
    echo "> PASS: Validator has not been jailed."
else
    echo "> FAIL: Validator has been jailed."
    exit 1
fi

