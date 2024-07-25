#!/bin/bash

# Requires env
# MAX_BYTES
# MAX_GAS
# EVIDENCE_MAX_AGE_NUM_BLOCKS
# EVIDENCE_MAX_AGE_DURATION
# EVIDENCE_MAX_BYTES

# Patch prop template
sed "s/_MAX_BYTES_/$MAX_BYTES/g" templates/proposal-block-params.json > templates/proposal-block-params-patched.json.tmp
mv templates/proposal-block-params-patched.json.tmp templates/proposal-block-params-patched.json
sed "s/_MAX_GAS_/$MAX_GAS/g" templates/proposal-block-params-patched.json > templates/proposal-block-params-patched.json.tmp
mv templates/proposal-block-params-patched.json.tmp templates/proposal-block-params-patched.json
sed "s/_EVIDENCE_MAX_AGE_NUM_BLOCKS_/$EVIDENCE_MAX_AGE_NUM_BLOCKS/g" templates/proposal-block-params-patched.json > templates/proposal-block-params-patched.json.tmp
mv templates/proposal-block-params-patched.json.tmp templates/proposal-block-params-patched.json
sed "s/_EVIDENCE_MAX_AGE_DURATION_/$EVIDENCE_MAX_AGE_DURATION/g" templates/proposal-block-params-patched.json > templates/proposal-block-params-patched.json.tmp
mv templates/proposal-block-params-patched.json.tmp templates/proposal-block-params-patched.json
sed "s/_EVIDENCE_MAX-BYTES_/$EVIDENCE_MAX_BYTES/g" templates/proposal-block-params-patched.json > templates/proposal-block-params-patched.json.tmp
mv templates/proposal-block-params-patched.json.tmp templates/proposal-block-params-patched.json

echo "Proposal file:"
cat templates/proposal-block-params-patched.json

# Submit Proposal
echo "Submitting proposal..."
proposal="$CHAIN_BINARY tx gov submit-proposal templates/proposal-block-params-patched.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y -o json"
echo $proposal
gaiadout=$($proposal)
echo "gaiad output:"
echo "$gaiadout"
echo "$gaiadout" > ~/artifact/$CHAIN_ID-tx-ratelimit.txt

txhash=$(echo "$gaiadout" | jq -r .txhash)
# Wait for the proposal to go on chain
sleep 6

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
$CHAIN_BINARY q tx $txhash --home $HOME_1
proposal_id=$($CHAIN_BINARY q tx $txhash --home $HOME_1 --output json | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "Voting on proposal $proposal_id..."
$CHAIN_BINARY tx gov vote $proposal_id yes --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --from $WALLET_1 --keyring-backend test --home $HOME_1 --chain-id $CHAIN_ID -b sync -y
$CHAIN_BINARY q gov tally $proposal_id --home $HOME_1
echo "Waiting for proposal to pass..."
sleep $VOTING_PERIOD

$CHAIN_BINARY q gov proposal $proposal_id --home $HOME_1
echo "Get params:"
curl http://127.0.0.1:$VAL1_API_PORT/cosmos/consensus/v1/params
