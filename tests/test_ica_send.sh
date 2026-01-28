#!/bin/bash
controller=$1
recipient=$2

ica_address=$($CHAIN_BINARY q interchain-accounts controller interchain-account $controller $ica_connection_id --home $whale_home -o json | jq -r '.address')
echo "> ICA address: $ica_address"

echo "> ICA balance in secondary chain:"
source scripts/vars_ica.sh
$CHAIN_BINARY q bank balances $ica_address --home $whale_home -o json | jq '.'

echo "ICA tx recipient in secondary chain:"
$CHAIN_BINARY q bank balances $recipient --home $whale_home -o json | jq '.'

source scripts/vars.sh
jq -r --arg FROMADDRESS "$ica_address" '.from_address = $FROMADDRESS' templates/ica-msg-send.json > msg-from.json
jq -r --arg TOADDRESS "$recipient" '.to_address = $TOADDRESS' msg-from.json > msg.json

echo "ICA Message:"
jq '.' msg.json
$CHAIN_BINARY tx interchain-accounts host generate-packet-data "$(cat msg.json)" --encoding proto3 > send_packet.json
echo "Sending ICA tx..."
$CHAIN_BINARY tx interchain-accounts controller send-tx $ica_connection_id send_packet.json --from $controller --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home
sleep 60

source scripts/vars_ica.sh
ica_balance=$($CHAIN_BINARY q bank balances $ica_address --home $whale_home -o json | jq -r '.balances[] | select(.denom == "uatom").amount')
recipient_balance=$($CHAIN_BINARY q bank balances $recipient --home $whale_home -o json | jq -r '.balances[] | select(.denom == "uatom").amount')

echo "ICA balance in secondary chain: $ica_balance"
echo "ICA tx recipient in secondary chain: $recipient_balance"
echo "Full balance query response:"
$CHAIN_BINARY q bank balances $recipient --home $whale_home -o json | jq -r '.'
if [ $recipient_balance == "5555555" ]; then
    echo "PASS: Account in host chain received funds from ICA."
else
    echo "FAIL: Account in host chain did not receive funds from ICA."
    exit 1
fi
