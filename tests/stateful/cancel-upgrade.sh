#!/bin/bash
set -e

# Get current height
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)

upgrade_height=$(($current_block+$UPGRADE_AFTER))
echo "Submitting the upgrade proposal..."
echo "Upgrade Name set to: $UPGRADE_NAME"
echo "Upgrade height set to: $upgrade_height"

jq ".messages[].plan .height=$upgrade_height | .messages[].plan .name=\"$UPGRADE_NAME\"" templates/proposal-software-upgrade.json > upgrade_prop.json
scripts/submit_proposal.sh upgrade_prop.json

echo "[INFO]: Upgrade plan:"
upgrade_plan=$($CHAIN_BINARY --home $HOME_1 q upgrade plan -o json)
echo $upgrade_plan

# Check if plan is not empty
if [ "$upgrade_plan" == "{}" ]
then
    echo "[ERROR]: Upgrade plan is empty"
    exit 1
fi

# Check if upgrade plan matches prop height
upgrade_plan_height=$(echo $upgrade_plan | jq -r '.plan.height')
if [ "$upgrade_height" != "$upgrade_plan_height" ]
then
    echo "[ERROR]: Upgrade plan upgrade height different than proposal"
    echo "Expected $upgrade_height got $upgrade_plan_height"
    exit 1
fi

# Submit cancel proposal
scripts/submit_proposal.sh templates/proposal-cancel-software-upgrade.json

echo "Wait until upgrade height is reached"
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
echo $current_block
until [[ "${current_block}" -gt "${upgrade_height}" ]]
do
    current_block=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ $echo_height -ne $current_block ]
    then
        echo "[INFO] Current height: $current_block"
        echo_height=$current_block
    fi
    sleep 1
done

echo "[INFO]: $CHAIN_BINARY --home $HOME_1 q upgrade plan -o json"
post_upgrade_plan=$($CHAIN_BINARY --home $HOME_1 q upgrade plan -o json)
echo $upgrade_plan

# Check if plan is empty
if [ "$upgrade_plan" != "{}" ]
then
    echo "[ERROR]: Upgrade plan is not empty"
    exit 1
fi

# Make sure gaiad is still running
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
