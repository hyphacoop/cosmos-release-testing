#!/bin/bash
set -e

vote_option="$2"

if [ ! $vote_option ]
then
    vote_option="yes"
fi

# Generic submit proposal script
# ./submit_proposal.sh <path/to/prop/file> 

# Submit Proposal
echo "[INFO] Submitting proposal..."
proposal="$CHAIN_BINARY tx gov submit-proposal $1 --gas auto --gas-prices $GAS_PRICES$DENOM --gas-adjustment $GAS_ADJUSTMENT --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo "[INFO] Submit output:"
echo $proposal
gaiadout=$($proposal)
echo "[INFO] gaiad output:"
echo "$gaiadout"

txhash=$(echo "$gaiadout" | jq -r .txhash)
# Wait for the proposal to go on chain
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

# Get proposal ID from txhash
echo "[INFO] Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_tx_json=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json)
export PROPOSAL_TX_JSON=$proposal_tx_json
proposal_id=$(echo $proposal_tx_json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "[INFO] Voting on proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id $vote_option --gas auto --gas-prices $GAS_PRICES$DENOM --gas-adjustment $GAS_ADJUSTMENT --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo "[INFO] tx output:"
echo $vote
gaiadout=$($vote)
echo "[INFO] gaiad output:"
echo "$gaiadout"
txhash=$(echo "$gaiadout" | jq -r .txhash)

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

vote_tx_json=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json)
export VOTE_TX_JSON=$vote_tx_json

$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1
echo "[INFO] Waiting for proposal to pass..."
sleep $VOTING_PERIOD

echo "[INFO] Proposal status:"
proposal_status=$($CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1 -o json)
echo $proposal_status | jq -r '.'
export PROPOSAL_STATUS=$proposal_status
