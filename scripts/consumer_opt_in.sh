#!/bin/bash
# Opt in to consumer chain

echo "> Creating arrays"
monikers=()
homes=()
rpc_ports=()
for i in $(seq -w 01 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$consumer_home_prefix$i
    homes+=($home)
done

$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json --node http://localhost:$whale_rpc | jq -r '.chains[]'
echo "Consumer ID: $CONSUMER_ID"

echo "> Submitting opt-in txs"
for i in $(seq 0 $[validator_count-1])
do
    echo "> Opting in with ${monikers[i]}."
    pubkey=$($CHAIN_BINARY comet show-validator --home ${homes[i]})
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $pubkey --from ${monikers[i]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y -o json | jq -r '.txhash')
done

sleep $COMMIT_TIMEOUT