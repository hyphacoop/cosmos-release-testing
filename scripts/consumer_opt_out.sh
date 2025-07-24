#!/bin/bash
# Initialize a consumer chain

echo "Running with $CONSUMER_CHAIN_BINARY."

echo "> Creating arrays"
monikers=()
for i in $(seq -w 01 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
done

$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json --node http://localhost:$whale_rpc | jq -r '.chains[]'
echo "Consumer ID: $CONSUMER_ID"

echo "> Submitting opt-out txs"
for i in $(seq 0 $[validator_count-1])
do
    echo "> Opting out with ${monikers[i]}."
    txhash=$($CHAIN_BINARY tx provider opt-out --from ${monikers[i]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y -o json | jq -r '.txhash')
done

sleep $(($COMMIT_TIMEOUT*3))
$CHAIN_BINARY q provider params --home $whale_home
