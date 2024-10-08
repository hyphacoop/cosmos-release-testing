#!/bin/bash

ica_address=$($CHAIN_BINARY q interchain-accounts controller interchain-account $CONTROLLER_ACCT connection-0 --home $CONTROLLER_HOME -o json | jq -r '.address')
echo "ICA address: $ica_address"

echo "ICA balance in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $HOST_HOME -o json | jq '.'
echo "ICA tx recipient in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $RECIPIENT --home $HOST_HOME -o json | jq '.'

jq -r --arg FROMADDRESS "$ica_address" '.from_address = $FROMADDRESS' templates/ica-msg-send.json > msg-from.json
jq -r --arg TOADDRESS "$RECIPIENT" '.to_address = $TOADDRESS' msg-from.json > msg.json
echo "ICA Message:"
jq '.' msg.json
$CHAIN_BINARY tx interchain-accounts host generate-packet-data "$(cat msg.json)" --encoding proto3 > send_packet.json
echo "Sending ICA tx..."
$CHAIN_BINARY tx interchain-accounts controller send-tx connection-0 send_packet.json --from $CONTROLLER_ACCT --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $CONTROLLER_HOME
sleep 60

ica_balance=$($CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $HOST_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')
recipient_balance=$($CHAIN_BINARY_SECONDARY q bank balances $RECIPIENT --home $HOST_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

echo "ICA balance in secondary chain: $ica_balance"
echo "ICA tx recipient in secondary chain: $recipient_balance"
echo "Full balance query response:"
$CHAIN_BINARY_SECONDARY q bank balances $RECIPIENT --home $HOST_HOME -o json | jq -r '.'
if [ $recipient_balance == "5555555" ]; then
    echo "PASS: Account in host chain received funds from ICA."
else
    echo "FAIL: Account in host chain did not receive funds from ICA."
    exit 1
fi
