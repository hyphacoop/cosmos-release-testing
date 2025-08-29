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
echo "[INFO]: 1% is: $supply_one_percent"

echo "[INFO]: transfer 1%+2 uatom of total supply"
set +e
let tx_1_amount=$supply_one_percent+2
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $WALLET_1 $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful above the quota"
    exit 1
else
    echo "[PASS]: TX was not successful"
fi
set -e

echo "[INFO]: transfer 1%-2 uatom of total supply"
set +e
let tx_2_amount=$supply_one_percent-2
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $WALLET_1 $tx_2_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful"
fi

# wait for tx block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10
echo "[INFO]: tx_json"
echo "$tx_json"
txhash=$(echo $tx_json | jq -r '.txhash')

$CHAIN_BINARY q tx $txhash

