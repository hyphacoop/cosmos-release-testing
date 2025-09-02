#!/bin/bash
set -e

echo "[INFO]: Get current total supply"
total_uatom_supply=$($CHAIN_BINARY --home $HOME_1 q bank total-supply-of uatom -o json | jq -r '.amount.amount')

echo "[INFO]: Current uatom supply"
echo $total_uatom_supply

echo "[INFO]: Get bank balance of $WALLET_1"
wallet1_bank_balance=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
echo "$wallet1_bank_balance"

echo "[INFO]: Calculate 1% of supply"
supply_one_percent=$(printf %.0f $(echo "$total_uatom_supply*0.01" | bc -l))

echo "[INFO]: Calculate 0.9% of supply"
supply_09_percent=$(printf %.0f $(echo "$total_uatom_supply*0.009" | bc -l))

echo "[INFO]: 1% is: $supply_one_percent"

echo "[INFO]: transfer 1% uatom of total supply"
set +e
let tx_1_amount=$supply_one_percent
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $WALLET_1 $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful above the quota"
    exit 1
else
    echo "[PASS]: TX was not successful"
fi
set -e

echo "[INFO]: transfer 0.9% uatom of total supply"
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $WALLET_1 $supply_09_percent$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)

# wait for tx block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Query tx"
txhash=$(echo $tx_json | jq -r '.txhash')

code=$($CHAIN_BINARY --home $HOME_1 q tx $txhash -o json | jq '.code')

if [ $code -eq 0 ]
then
    echo "[PASS]: TX was successful"
fi
