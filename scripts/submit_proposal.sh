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
sleep 6

# Get proposal ID from txhash
echo "[INFO] Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "[INFO] Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id $vote_option --gas auto --gas-prices $GAS_PRICES$DENOM --gas-adjustment $GAS_ADJUSTMENT --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1
echo "[INFO] Waiting for proposal to pass..."
sleep $VOTING_PERIOD

echo "[INFO] Proposal status:"
$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1 -o json
