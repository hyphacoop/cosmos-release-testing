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

consumer_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.events[] | select(.type=="consumer_creation") | .attributes[] | select(.key=="consumer_id") | .value')
echo "[INFO]: Consumer ID: $consumer_id"
echo "CONSUMER_ID=$consumer_id" >> $GITHUB_ENV

echo "[INFO] Optin first validator"
node_key1=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_1 tendermint show-validator)
$CHAIN_BINARY --home $HOME_1 tx provider opt-in $consumer_id "$node_key1" --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 -y

tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO] Optin second validator"
node_key2=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_2 tendermint show-validator)
$CHAIN_BINARY --home $HOME_2 tx provider opt-in $consumer_id "$node_key2" --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from val2 -y

echo "[INFO] Waiting for proposal to pass..."
sleep $VOTING_PERIOD
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

#$CHAIN_BINARY q gov proposals --home $HOME_1

echo "[INFO] Collecting the CCV state..."
$CHAIN_BINARY q provider consumer-genesis $consumer_id -o json --home $HOME_1 > ccv-pre.json
$CHAIN_BINARY q provider consumer-genesis $consumer_id -o json --home $HOME_1 >  ~/artifact/$CONSUMER_CHAIN_ID-ccv-pre.txt
jq '.params |= . + {"soft_opt_out_threshold": "0.05"}' ccv-pre.json > ccv.json
jq '.' ccv.json

if [ ! -z $transform ]
then
    echo "[INFO] Patching CCV for backwards compatibility"
    wget https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd -O ics-transform
    chmod +x ics-transform
    ./ics-transform genesis transform --to $transform ccv.json > ccv-transform.json
    cp ccv-transform.json ccv.json
fi

cp ccv.json ~/artifact/$CONSUMER_CHAIN_ID-ccv.json

echo "[INFO] Patching the consumer genesis file..."
jq -s '.[0].app_state.ccvconsumer = .[1] | .[0]' $CONSUMER_HOME_1/config/genesis.json ccv.json > consumer-genesis.json
cp consumer-genesis.json $CONSUMER_HOME_1/config/genesis.json
cp consumer-genesis.json $CONSUMER_HOME_2/config/genesis.json

echo "[INFO] Starting the consumer chain..."
# Run service in screen session
echo "[INFO] Starting $CONSUMER_CHAIN_BINARY val1"
screen -L -Logfile $HOME/artifact/$CONSUMER_SERVICE_1.log -S $CONSUMER_SERVICE_1 -d -m bash $HOME/$CONSUMER_SERVICE_1.sh
# set screen to flush log to 0
screen -r $CONSUMER_SERVICE_1 -p0 -X logfile flush 0

echo "[INFO] Starting $CONSUMER_CHAIN_BINARY val2"
screen -L -Logfile $HOME/artifact/$CONSUMER_SERVICE_2.log -S $CONSUMER_SERVICE_2 -d -m bash $HOME/$CONSUMER_SERVICE_2.sh
# set screen to flush log to 0
screen -r $CONSUMER_SERVICE_2 -p0 -X logfile flush 0

# sleep 20
# sudo journalctl -u $CONSUMER_SERVICE_1 | tail -n 200
# sudo journalctl -u $CONSUMER_SERVICE_2 | tail -n 200
