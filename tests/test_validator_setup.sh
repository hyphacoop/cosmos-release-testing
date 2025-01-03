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
echo "> Key add output: $key"
echo "> Address: $address"
address_bytes=$($CHAIN_BINARY keys parse $address --output json | jq -r '.bytes')
$CHAIN_BINARY keys parse $address_bytes --output json | jq -r '.'

echo "> Receive funds"
$CHAIN_BINARY tx bank send $WALLET_1 $address $VAL_WHALE$DENOM --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $(($TIMEOUT_COMMIT*2))
$CHAIN_BINARY q bank balances $address -o json --home $home | jq '.'

echo "> Create validator"
pubkey=$($CHAIN_BINARY tendermint show-validator --home $home)
echo "> Patch pubkey: $pubkey"
jq -r --argjson PUBKEY $pubkey '.pubkey |= $PUBKEY' templates/create-validator.json > validator-pubkey.json
echo "> Patch stake amount: $VAL_STAKE$DENOM"
jq -r --arg STAKE "$VAL_STAKE$DENOM" '.amount |= $STAKE' validator-pubkey.json > validator-stake.json
jq '.' validator-stake.json
$CHAIN_BINARY tx staking create-validator validator-stake.json --from $address --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $home -y
sleep $(($TIMEOUT_COMMIT*2))
echo "> Validators:"
$CHAIN_BINARY q staking validators -o json --home $home | jq '.validators[].operator_address'
$CHAIN_BINARY q staking validators -o json --home $home | jq '.validators[].description.moniker'

echo "> Edit validator metadata"
$CHAIN_BINARY tx staking edit-validator --new-moniker "new-validator" --from $address --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $home -y
sleep $(($TIMEOUT_COMMIT*2))
echo "> Validators:"
$CHAIN_BINARY q staking validators -o json --home $home | jq '.validators[].operator_address'
$CHAIN_BINARY q staking validators -o json --home $home | jq '.validators[].description.moniker'

echo "> Verify validator is signing blocks"
consensus_address=$(jq -r '.address' $home/config/priv_validator_key.json)
echo "> Consensus address: $consensus_address"
$CHAIN_BINARY tendermint show-address --home $home
sleep $(($TIMEOUT_COMMIT*2))
echo "> Last commit signatures:"
curl -s http://localhost:$rpc_port/block | jq -r '.result.block.last_commit.signatures'

