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

echo "> Moniker: ${monikers[-1]}"
wallet=$($CHAIN_BINARY keys list --output json --home $whale_home | jq -r --arg name "${monikers[-1]}" '.[] | select(.name==$name).address')
echo "> Wallet: $wallet"
bytes=$($CHAIN_BINARY keys parse $wallet --output json --home $whale_home | jq -r '.bytes')
echo "> Bytes: $bytes"
valoper=$($CHAIN_BINARY keys parse $bytes --output json --home $whale_home | jq -r '.formats[2]')
echo "> Valoper: $valoper"

# Jailing

echo "> Stopping the last validator's consumer node."
session=${consumer_monikers[-1]}
echo "> Session: $session"
tmux send-keys -t $session C-c
sleep 5
tail ${logs[-1]} -n 100
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

status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).status')
echo "> Status: $status"
if [[ "$status" == "BOND_STATUS_UNBONDING" ]]; then
    echo "> PASS: Validator has been jailed."
else
    echo "> FAIL: Validator has not been jailed."
    exit 1
fi

# Unjailing

echo "> Starting the last validator's consumer node again."
tmux new-session -d -s $session "$CONSUMER_CHAIN_BINARY start --home ${homes[-1]} 2>&1 | tee ${logs[-1]}"
sleep $DOWNTIME_JAIL_DURATION
tail ${logs[-1]}
echo "> Submitting unjail transaction."
$CHAIN_BINARY tx slashing unjail --from ${monikers[-1]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Wait for consumer chain to submit another downtime infraction."
sleep $(($COMMIT_TIMEOUT*$CONSUMER_DOWNTIME_WINDOW))
sleep $(($COMMIT_TIMEOUT*10))
status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).status')
echo "> Status: $status"
if [[ "$status" == "BOND_STATUS_BONDED" ]]; then
    echo "> PASS: Validator has been unjailed."
else
    echo "> FAIL: Validator has not been unjailed."
    exit 1
fi