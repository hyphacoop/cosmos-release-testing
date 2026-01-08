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

echo "[INFO]: Calculate 2% of supply"
supply_two_percent=$(printf %.0f $(echo "$total_uatom_supply*0.02" | bc -l))
echo "$supply_two_percent"

echo "[INFO]: Calculate 1.9% of supply"
supply_19_percent=$(printf %.0f $(echo "$total_uatom_supply*0.019" | bc -l))
echo "$supply_19_percent"

echo "[INFO]: 2% is: $supply_two_percent"

echo "[INFO]: transfer 1% uatom of total supply"
set +e
let tx_1_amount=$supply_two_percent
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $consumer_test_wallet1_addr $tx_1_amount$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
if [ $? -eq 0 ]
then
    echo "[ERROR]: TX was successful above the quota"
    exit 1
else
    echo "[PASS]: TX was not successful"
fi
set -e

echo "[INFO]: transfer 0.9% uatom of total supply"
tx_json=$($CHAIN_BINARY --home $HOME_1 tx ibc-transfer transfer transfer $CONSUMERA_CHAN_ID $consumer_test_wallet1_addr $supply_19_percent$DENOM --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)

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
current_amount=$($CONSUMER_CHAIN_BINARY --home $CONSUMER_HOME_1 q bank balances $consumer_test_wallet1_addr -o json | jq -r '.balances[0].amount')

echo "[INFO]: Consumer wallet $consumer_test_wallet1_addr amount $current_amount"

if [ $supply_19_percent -eq $current_amount  ]
then
    echo "[PASS]: $consumer_test_wallet1_addr received correct amount of tokens over IBC"
else
    echo "[ERROR]: $consumer_test_wallet1_addr received incorrect amount"
    exit 1
fi
