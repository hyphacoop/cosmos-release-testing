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

echo "> Finding first validator with BONDED status."
moniker=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r '[.validators[] | select(.status=="BOND_STATUS_BONDED")][1].description.moniker')
echo "> Moniker: $moniker"
valoper=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg moniker "$moniker" '.validators[] | select(.description.moniker==$moniker).operator_address')
echo "> Valoper: $valoper"
wallet=$($CHAIN_BINARY keys list --output json --home $whale_home | jq -r --arg name "$moniker" '.[] | select(.name==$name).address')
echo "> Wallet: $wallet"
echo "> OR, alternatively, using valoper address:"
bytes=$($CHAIN_BINARY keys parse $valoper --output json --home $whale_home | jq -r '.bytes')
echo "> Bytes: $bytes"
wallet=$($CHAIN_BINARY keys parse $bytes --output json --home $whale_home | jq -r '.formats[0]')
echo "> Wallet: $wallet"

exit 0

echo "> Moniker: ${monikers[1]}"
wallet=$($CHAIN_BINARY keys list --output json --home $whale_home | jq -r --arg name "${monikers[2]}" '.[] | select(.name==$name).address')
echo "> Wallet: $wallet"
bytes=$($CHAIN_BINARY keys parse $wallet --output json --home $whale_home | jq -r '.bytes')
echo "> Bytes: $bytes"
valoper=$($CHAIN_BINARY keys parse $bytes --output json --home $whale_home | jq -r '.formats[2]')
echo "> Valoper: $valoper"

echo "> Slashing parameters:"
$CHAIN_BINARY q slashing params --home $whale_home -o json | jq '.'

# Jailing
echo "> Stopping the last validator's node."
session=${monikers[2]}
echo "> Session: $session"
tmux send-keys -t $session C-c
sleep $((COMMIT_TIMEOUT*3))
tail ${logs[2]} -n 100
echo "> Waiting for the downtime infraction."
sleep $(($COMMIT_TIMEOUT*$DOWNTIME_WINDOW))

echo "> Valset:"
$CHAIN_BINARY q comet-validator-set --home $whale_home -o json | jq '.'
echo "> Validators:"
$CHAIN_BINARY q staking validators --home $whale_home -o json | jq '.'
echo "> Slashing:"
$CHAIN_BINARY q slashing signing-infos --home $whale_home -o json | jq '.'

status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).status')
echo "> Status: $status"
if [[ "$status" == "BOND_STATUS_UNBONDING" ]]; then
    echo "> PASS: Validator is unbonding."
else
    echo "> FAIL: Validator is not unbonding."
    exit 1
fi
jailed=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).jailed')
if [[ "$jailed" == "true" ]]; then
    echo "> PASS: Validator is jailed."
else
    echo "> FAIL: Validator is not jailed."
    exit 1
fi

# Unjailing

echo "> Starting the last validator's node again."
tmux new-session -d -s $session "$CHAIN_BINARY start --home ${homes[2]} 2>&1 | tee ${logs[2]}"
echo "> Waiting for the downtime infraction to expire."
sleep $DOWNTIME_JAIL_DURATION
tail ${logs[2]} -n 100
echo "> Submitting unjail transaction."
$CHAIN_BINARY tx slashing unjail --from ${monikers[2]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Wait for another downtime infraction."
sleep $(($COMMIT_TIMEOUT*5))
status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).status')
echo "> Status: $status"
if [[ "$status" == "BOND_STATUS_BONDED" ]]; then
    echo "> PASS: Validator is bonded."
else
    echo "> FAIL: Validator is not bonded."
    exit 1
fi

jailed=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r --arg addr "$valoper" '.validators[] | select(.operator_address==$addr).jailed')
echo "> Jailed: $jailed"
