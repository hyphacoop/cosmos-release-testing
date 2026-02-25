#!/bin/bash
set -e
# Launch a consumer chain
# $1 sets the backwards compatibility version

# set spawn time 1 minute from now
spawn="1 minute"

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
set +e
output=$($CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json 2>&1 1>/dev/null)

if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful"
    exit 1
else
    echo "[PASS]: TX was not successful"
fi

echo "[INFO]: Gaiad output:"
echo $output

echo $output | grep "MsgCreateConsumer is disabled"
if [ $? -eq 0 ]
then
    echo "[PASS]: Got MsgCreateConsumer is disabled message"
else
    echo "[ERROR]: MsgCreateConsumer is disabled message not detected!"
    exit 1
fi
