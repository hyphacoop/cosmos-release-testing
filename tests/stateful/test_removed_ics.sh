#!/bin/bash
set -e
# Launch a consumer chain
# $1 sets the backwards compatibility version

transform=$1
debug=1
# set spawn time 1 minute from now
spawn="1 minute"

if [ $debug -eq 1 ]
then
    echo "[DEBUG] ADD TEMPLATE templates/create-consumer-stateful.json:"
    cat templates/create-consumer-stateful.json
fi

echo "[INFO] Patching add template with spawn time..."
spawn_time=$(date --date="$spawn" -u --iso-8601=ns | sed s/+00:00/Z/ | sed s/,/./)
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' templates/create-consumer-stateful.json > create-spawn.json
if [ $debug -eq 1 ]
then
    echo "[DEBUG] ADD FILE AFTER ADD SPAWN create-spawn.json:"
    cat create-spawn.json
fi
sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" create-spawn.json > create-$CONSUMER_CHAIN_ID.json
rm create-spawn.json
if [ $debug -eq 1 ]
then
    echo "[DEBUG] CREATE SPAWN FILE AFTER SET chain_id create-$CONSUMER_CHAIN_ID.json:"
    cat create-$CONSUMER_CHAIN_ID.json
fi

if [ $PSS_ENABLED == true ]; then
    echo "[INFO] Patching for PSS..."
    jq -r --argjson TOPN $TOPN '.messages[0].top_N |= $TOPN' create-$CONSUMER_CHAIN_ID.json > create-topn.json
    mv create-topn.json create-$CONSUMER_CHAIN_ID.json
fi

if [ $debug -eq 1 ]
then
    echo "[DEBUG] CREATE FILE AFTER SET PSS create-$CONSUMER_CHAIN_ID.json:"
    cat create-$CONSUMER_CHAIN_ID.json
fi

echo "[INFO] Create file create-$CONSUMER_CHAIN_ID.json"
jq -r '.' create-$CONSUMER_CHAIN_ID.json
cp create-$CONSUMER_CHAIN_ID.json ~/artifact/

echo "[INFO] Submitting transection..."
transection="$CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo $transection
gaiadout=$($transection)
echo "[INFO] gaiad output:"
echo "$gaiadout"
echo "$gaiadout" > ~/artifact/$CONSUMER_CHAIN_ID-tx.txt

txhash=$(echo "$gaiadout" | jq -r .txhash)

tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: TX results:"
$CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.'
