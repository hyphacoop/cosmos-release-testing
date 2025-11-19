#!/bin/bash

RCV_FEE=1000000
ACK_FEE=2000000
TIMEOUT_FEE=3000000
balance_before=$($CHAIN_BINARY q bank balances $WALLET_RELAYER --home $HOME_1 -o json | jq -r --arg DENOM "$DENOM" '.balances[] | select(.denom == $DENOM).amount')


hermes --json create channel --order unordered --a-chain $CHAIN_ID --a-port transfer --b-port transfer --a-connection connection-0 --channel-version "{\"fee_version\":\"ics29-1\",\"app_version\":\"ics20-1\"}"

txhash=$($CHAIN_BINARY tx ibc-transfer transfer transfer channel-0 $WALLET_1 1$DENOM --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT --from $WALLET_1 --output json -y --home $HOME_1 | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
sequence=$($CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq -r '.events[] | select(.type == "send_packet").attributes[] | select(.key == "packet_sequence").value')
$CHAIN_BINARY tx ibc-fee pay-packet-fee transfer channel-0 $sequence --recv-fee ${RCV_FEE}$DENOM --ack-fee ${ACK_FEE}$DENOM --timeout-fee ${TIMEOUT_FEE}$DENOM --from $WALLET_1 --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT --home $HOME_1 -y

sleep 30
balance_after=$($CHAIN_BINARY q bank balances $WALLET_RELAYER --home $HOME_1 -o json | jq -r --arg DENOM "$DENOM" '.balances[] | select(.denom == $DENOM).amount')
difference=$(echo "$balance_after - $balance_before" | bc)
echo "Balance before: $balance_before$DENOM"
echo "Balance after: $balance_after$DENOM"
echo "Difference: ${difference}$DENOM"

if (( $(echo "$balance_after > $balance_before" | bc -l) )); then
    echo "PASS: Relayer balance increased."
else
    echo "FAIL: Relayer balance did not increase."
    exit 1
fi