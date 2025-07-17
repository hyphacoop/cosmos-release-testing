#!/bin/bash
# Get current height
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)

upgrade_height=$(($current_block+$UPGRADE_AFTER))
echo "Submitting the upgrade proposal..."
echo "Upgrade Name set to: $UPGRADE_NAME"
echo "Upgrade height set to: $upgrade_height"

jq ".messages[].plan .height=$upgrade_height | .messages[].plan .name=\"$UPGRADE_NAME\"" templates/proposal-software-upgrade.json > upgrade_prop.json
scripts/submit_proposal.sh upgrade_prop.json

$CHAIN_BINARY q upgrade plan -o json
