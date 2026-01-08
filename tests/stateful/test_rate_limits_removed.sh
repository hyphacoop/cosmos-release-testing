#!/bin/bash
set -e

echo "[INFO]: Creating new consumer wallet..."

number=$(date +%s)
wallet_name=$(echo "vesting-$number")
consumer_test_wallet1_json=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_1 keys add $wallet_name --output json)
consumer_test_wallet1_addr=$(echo $consumer_test_wallet1_json | jq -r '.address')

echo "[INFO]: Consumer test wallet: $consumer_test_wallet1_addr"

echo "[INFO]: Get current total supply"
total_uatom_supply=$($CHAIN_BINARY --home $HOME_1 q bank total-supply-of uatom -o json | jq -r '.amount.amount')

echo "[INFO]: Current uatom supply"
echo $total_uatom_supply

echo "[INFO]: Get bank balance of $WALLET_1"
wallet1_bank_balance=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
echo "$wallet1_bank_balance"

echo "[INFO]: Calculate 5% of supply"
supply_five_percent=$(printf %.0f $(echo "$total_uatom_supply*0.05" | bc -l))
echo "$supply_five_percent"

echo "[INFO]: Calculate 1.9% of supply"
supply_19_percent=$(printf %.0f $(echo "$total_uatom_supply*0.019" | bc -l))
echo "$supply_19_percent"

echo "[INFO]: 5% is: $supply_five_percent"

echo "[INFO]: transfer 5% uatom of total supply"
let tx_1_amount=$supply_five_percent
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $consumer_test_wallet1_addr $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[PASS]: TX was successful"
else
    echo "[FAIL]: TX was not successful"
    exit 1
fi
