#!/bin/bash
set -e

echo "[INFO]: Creating new consumer wallet..."
secondary_test_wallet1_json=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME keys add rate-limit-1 --output json)
secondary_test_wallet1_addr=$(echo $secondary_test_wallet1_json | jq -r '.address')

echo "[INFO]: Consumer test wallet: $secondary_test_wallet1_addr"

echo "[INFO]: Get current total supply"
total_uatom_supply=$($CHAIN_BINARY --home $HOME_1 q bank total-supply-of uatom -o json | jq -r '.amount.amount')

echo "[INFO]: Current uatom supply"
echo $total_uatom_supply

echo "[INFO]: Get bank balance of $WALLET_1"
wallet1_bank_balance=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r '.balances[] | select(.denom=="uatom") | .amount')
echo "$wallet1_bank_balance"

# echo "[DEBUG]: $CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r '.'"
# $CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r '.'

echo "[INFO]: Calculate 1% of supply"
supply_one_percent=$(printf %.0f $(echo "$total_uatom_supply*0.01" | bc -l))
echo "$supply_one_percent"

echo "[INFO]: Calculate 0.9% of supply"
supply_09_percent=$(printf %.0f $(echo "$total_uatom_supply*0.009" | bc -l))
echo "$supply_09_percent"

echo "[INFO]: 1% is: $supply_one_percent"

echo "[INFO]: transfer 1% uatom of total supply"
set +e
let tx_1_amount=$supply_one_percent
echo "$CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $SECONDARY_CHAN_ID $secondary_test_wallet1_addr $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json"
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $SECONDARY_CHAN_ID $secondary_test_wallet1_addr $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful above the quota"
    exit 1
else
    echo "[PASS]: TX was not successful"
fi
set -e

echo "[INFO]: transfer 0.9% uatom of total supply"
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $SECONDARY_CHAN_ID $secondary_test_wallet1_addr $supply_09_percent$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)

# wait for tx block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Query tx"
txhash=$(echo $tx_json | jq -r '.txhash')

code=$($CHAIN_BINARY --home $HOME_1 q tx $txhash -o json | jq '.code')

if [ $code -eq 0 ]
then
    echo "[PASS]: TX was successful"
fi

# query consumer chain balance
current_amount=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $secondary_test_wallet1_addr -o json | jq -r '.balances[0].amount')

echo "[INFO]: Consumer wallet $secondary_test_wallet1_addr amount $current_amount"

if [ $supply_09_percent -eq $current_amount  ]
then
    echo "[PASS]: $secondary_test_wallet1_addr received correct amount of tokens over IBC"
else
    echo "[ERROR]: $secondary_test_wallet1_addr received incorrect amount"
    exit 1
fi
