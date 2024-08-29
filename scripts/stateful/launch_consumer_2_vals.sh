#!/bin/bash
set -e
# Launch a consumer chain
# $1 sets the backwards compatibility version

transform=$1
debug=1

if [ $debug -eq 1 ]
then
    echo "[DEBUG] PROPOSAL TEMPLATE templates/proposal-add-template.json:"
    cat templates/proposal-add-template.json
fi

echo "[INFO] Patching add template with spawn time..."
spawn_time=$(date -u --iso-8601=ns | sed s/+00:00/Z/ | sed s/,/./)
jq -r --arg SPAWNTIME "$spawn_time" '.messages[0].spawn_time |= $SPAWNTIME' templates/proposal-add-template.json > proposal-add-spawn.json
if [ $debug -eq 1 ]
then
    echo "[DEBUG] PROPOSAL FILE AFTER ADD SPAWN proposal-add-spawn.json:"
    cat proposal-add-spawn.json
fi
sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" proposal-add-spawn.json > proposal-add-$CONSUMER_CHAIN_ID.json
rm proposal-add-spawn.json
if [ $debug -eq 1 ]
then
    echo "[DEBUG] PROPOSAL AFTER SET chain_id proposal-add-$CONSUMER_CHAIN_ID.json:"
    cat proposal-add-$CONSUMER_CHAIN_ID.json
fi

if [ $PSS_ENABLED == true ]; then
    echo "[INFO] Patching for PSS..."
    jq -r --argjson TOPN $TOPN '.messages[0].top_N |= $TOPN' proposal-add-$CONSUMER_CHAIN_ID.json > proposal-add-topn.json
    mv proposal-add-topn.json proposal-add-$CONSUMER_CHAIN_ID.json
fi

if [ $debug -eq 1 ]
then
    echo "[DEBUG] PROPOSAL AFTER SET PSS proposal-add-$CONSUMER_CHAIN_ID.json:"
    cat proposal-add-$CONSUMER_CHAIN_ID.json
fi

echo "[INFO] Proposal file proposal-add-$CONSUMER_CHAIN_ID.json"
jq -r '.' proposal-add-$CONSUMER_CHAIN_ID.json
cp proposal-add-$CONSUMER_CHAIN_ID.json ~/artifact/

echo "[INFO] Submitting proposal..."
proposal="$CHAIN_BINARY tx gov submit-proposal proposal-add-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo $proposal
gaiadout=$($proposal)
echo "[INFO] gaiad output:"
echo "$gaiadout"
echo "$gaiadout" > ~/artifact/$CONSUMER_CHAIN_ID-tx.txt

txhash=$(echo "$gaiadout" | jq -r .txhash)
# Wait for the proposal to go on chain
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

# Get proposal ID from txhash
echo "[INFO] Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "[INFO] Optin first validator"
node_key1=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_1 tendermint show-validator)
$CHAIN_BINARY --home $HOME_1 tx provider opt-in $CONSUMER_CHAIN_ID "$node_key1" --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 -y

echo "[INFO] Optin second validator"
node_key2=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_2 tendermint show-validator)
$CHAIN_BINARY --home $HOME_1 tx provider opt-in $CONSUMER_CHAIN_ID "$node_key2" --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 -y

echo "[INFO] Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1

echo "[INFO] Waiting for proposal to pass..."
sleep $VOTING_PERIOD
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

#$CHAIN_BINARY q gov proposals --home $HOME_1

echo "[INFO] Collecting the CCV state..."
$CHAIN_BINARY q provider consumer-genesis $CONSUMER_CHAIN_ID -o json --home $HOME_1 > ccv-pre.json
$CHAIN_BINARY q provider consumer-genesis $CONSUMER_CHAIN_ID -o json --home $HOME_1 >  ~/artifact/$CONSUMER_CHAIN_ID-ccv-pre.txt
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
