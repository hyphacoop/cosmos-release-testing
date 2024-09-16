#!/bin/bash
set -e

echo "Getting connection ID from controller"
# client_id=$(hermes --json query clients --host-chain $CHAIN_ID | jq -r '.result[] | select(.chain_id == "ica-chain") | .client_id')
# echo "client ID: $client_id"
# connection_id=$(hermes  --json query client connections --client $client_id --chain $CHAIN_ID | jq -r '.result[0] | select (.!=null)')
connection_id=$(hermes --json query connection end --chain ica-chain --connection connection-0 | tail -n 1 | jq -r '.result.counterparty.connection_id')

echo "Connection ID: $connection_id"

echo "Registering ICA..."
$CHAIN_BINARY tx interchain-accounts controller register $connection_id --from $WALLET_1 --ordering ORDER_ORDERED --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM -y -o json --home $CHAIN_HOME --version ""
sleep 60

ica_address=$($CHAIN_BINARY q interchain-accounts controller interchain-account $WALLET_1 $connection_id --home $CHAIN_HOME -o json | jq -r '.address')
echo "ICA address: $ica_address"
echo "Funding ICA..."
$CHAIN_BINARY_SECONDARY tx bank send $WALLET_1 $ica_address 100000000$DENOM --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM -y -o json --home $ICA_HOME
sleep 10

echo "ICA balance in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $ICA_HOME -o json | jq '.'
echo "ICA tx recipient in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $WALLET_5 --home $ICA_HOME -o json | jq '.'

jq -r --arg ADDRESS "$ica_address" '.from_address = $ADDRESS' templates/ica-msg-send-stateful.json > msg.json
$CHAIN_BINARY tx interchain-accounts host generate-packet-data "$(cat msg.json)" --encoding proto3 > send_packet.json
echo "Sending ICA tx..."
$CHAIN_BINARY tx interchain-accounts controller send-tx $connection_id send_packet.json --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM -y -o json --home $CHAIN_HOME
sleep 60

ica_balance=$($CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $ICA_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')
recipient_balance=$($CHAIN_BINARY_SECONDARY q bank balances $WALLET_5 --home $ICA_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

echo "ICA balance in secondary chain: $ica_balance"
echo "ICA tx recipient in secondary chain: $recipient_balance"

recipient_balance=$($CHAIN_BINARY_SECONDARY q bank balances $WALLET_5 --home $ICA_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

if [ $recipient_balance == "5555555" ]; then
    echo "PASS: Account in host chain received funds from ICA."
else
    echo "FAIL: Account in host chain did not receive funds from ICA."
    exit 1
fi
