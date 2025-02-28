#!/bin/bash

echo "Registering ICA..."
$CHAIN_BINARY tx interchain-accounts controller register connection-0 --ordering ORDER_ORDERED --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $CONTROLLER_HOME
sleep 60

ica_address=$($CHAIN_BINARY q interchain-accounts controller interchain-account $WALLET_1 connection-0 --home $CONTROLLER_HOME -o json | jq -r '.address')
echo "ICA address: $ica_address"
echo "Funding ICA..."
$CHAIN_BINARY_SECONDARY tx bank send $WALLET_1 $ica_address 100000000$DENOM --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $HOST_HOME
sleep 10

echo "ICA balance in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $HOST_HOME -o json | jq '.'
echo "ICA tx recipient in secondary chain:"
$CHAIN_BINARY_SECONDARY q bank balances $WALLET_2 --home $HOST_HOME -o json | jq '.'

jq -r --arg ADDRESS "$ica_address" '.from_address = $ADDRESS' templates/ica-msg-send.json > msg.json
$CHAIN_BINARY tx interchain-accounts host generate-packet-data "$(cat msg.json)" --encoding proto3 > send_packet.json
echo "Sending ICA tx..."
$CHAIN_BINARY tx interchain-accounts controller send-tx connection-0 send_packet.json --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $CONTROLLER_HOME
sleep 60

ica_balance=$($CHAIN_BINARY_SECONDARY q bank balances $ica_address --home $HOST_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')
recipient_balance=$($CHAIN_BINARY_SECONDARY q bank balances $WALLET_2 --home $HOST_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

echo "ICA balance in secondary chain: $ica_balance"
echo "ICA tx recipient in secondary chain: $recipient_balance"

recipient_balance=$($CHAIN_BINARY_SECONDARY q bank balances $WALLET_2 --home $HOST_HOME -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

if [ $recipient_balance == "5555555" ]; then
    echo "PASS: Account in host chain received funds from ICA."
else
    echo "FAIL: Account in host chain did not receive funds from ICA."
    journalctl -u $RELAYER.service | tail -n 100
    exit 1
fi
