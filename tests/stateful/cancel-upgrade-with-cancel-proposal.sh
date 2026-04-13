#!/bin/bash
set -e

# Get current height
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)

upgrade_height=$(($current_block+$UPGRADE_AFTER))
echo "Submitting the upgrade proposal..."
echo "Upgrade Name set to: $UPGRADE_NAME"
echo "Upgrade height set to: $upgrade_height"

jq ".messages[].plan .height=$upgrade_height | .messages[].plan .name=\"$UPGRADE_NAME\"" templates/proposal-software-upgrade.json > upgrade_prop.json
echo "[INFO]: Submit upgrade proposal..."
source scripts/submit_proposal.sh upgrade_prop.json yes do-not-wait
# Wait for block to go on chain
cur_height=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
let to_height=$cur_height+1
echo_height=1
echo "[INFO] Current height: $cur_height"

until [[ "${cur_height}" -gt "${to_height}" ]]
do
    cur_height=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ $echo_height -ne $cur_height ]
    then
        echo "[INFO] Current height: $cur_height"
        echo_height=$cur_height
    fi
    sleep 1
done

echo "[INFO]: Upgrade plan:"
upgrade_plan=$($CHAIN_BINARY --home $HOME_1 q upgrade plan -o json)
echo $upgrade_plan

# Submit cancel proposal
proposal_id=$(echo $PROPOSAL_TX_JSON | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "[INFO]: Submitting TX gov cancel-proposal $proposal_id ..."
# $CHAIN_BINARY --home $HOME_1 tx gov cancel-proposal $proposal_id --gas auto --gas-prices $GAS_PRICES$DENOM --gas-adjustment $GAS_ADJUSTMENT --from $WALLET_1 --yes

# Wait for block to go on chain
cur_height=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
let to_height=$cur_height+1
echo_height=1
echo "[INFO] Current height: $cur_height"

until [[ "${cur_height}" -gt "${to_height}" ]]
do
    cur_height=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ $echo_height -ne $cur_height ]
    then
        echo "[INFO] Current height: $cur_height"
        echo_height=$cur_height
    fi
    sleep 1
done

# echo "[INFO]: Query proposal $proposal_id ..."
# set +e
# $CHAIN_BINARY --home $HOME_1 q gov proposal $proposal_id
# if [ $? != 0 ]
# then
#     echo "Proposal query failed as expected"
# else
#     echo "Proposal query successful, TEST FAILED"
#     exit 1
# fi
# set -e

# echo "[INFO]: Wait for orignal voting period to end"
# sleep $VOTING_PERIOD

# # Check if plan is empty
# echo "[INFO]: $CHAIN_BINARY --home $HOME_1 q upgrade plan -o json"
# post_upgrade_plan=$($CHAIN_BINARY --home $HOME_1 q upgrade plan -o json)
# echo $post_upgrade_plan
# if [ "$post_upgrade_plan" != "{}" ]
# then
#     echo "[ERROR]: Upgrade plan is not empty"
#     exit 1
# else
#     echo "[INFO]: Upgrade plan is empty"
# fi

echo "[INFO]: Wait until upgrade height is reached"
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
count=0
let check_height=$upgrade_height+5
until [ $current_block -gt $check_height ]
do
    current_block=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ "$echo_height" != "$current_block" ]
    then
        echo "[INFO] Current height: $current_block"
        echo_height=$current_block
        count=0
    fi
    let count=$count+1
    if [ $count -gt 20 ]
    then
        echo "[ERROR]: chain stopped at height: $current_block"
        exit 1
    fi
    sleep 1
done
