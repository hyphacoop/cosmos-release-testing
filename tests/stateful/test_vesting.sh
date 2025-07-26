#!/bin/bash
set -e

vesting_time="5 minutes"
vesting_amount=100000000

# Create a vesting account with 100 atom
echo "[INFO]: > Testing vesting account with $vesting_time"
vesting_wallet1_json=$($CHAIN_BINARY --home $HOME_1 keys add vesting-1 --output json)
echo "[INFO]: feemarket_wallet1: $vesting_wallet1_json"
vesting_wallet1_addr=$(echo $vesting_wallet1_json | jq -r '.address')

echo "[INFO]: Creating vesting wallet: $vesting_wallet1_addr"
vesting_end_time=$(date -d "+$vesting_time" +%s)
echo "[INFO]: Vesting end time: $vesting_end_time"
$CHAIN_BINARY --home $HOME_1 tx vesting create-vesting-account $vesting_wallet1_addr $vesting_amount$DENOM $vesting_end_time --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Wait until spendable balance matches vesting amount"
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
count=0
current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
echo "[INFO]: Current spendable balance: $current_spend_amount"

until [ $current_spend_amount -eq $vesting_amount ]
do
    current_block=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ "$echo_height" != "$current_block" ]
    then
        echo "[INFO] Current height: $current_block"
        current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
        echo "[INFO]: Current spendable balance: $current_spend_amount"
        echo_height=$current_block
        count=0
    fi
    let count=$count+1
    if [ $count -gt 20 ]
    then
        echo "[ERROR]: chain stopped at height: $current_block"
        exit 1
    fi
    sleep 1
done

block_timestamp=$($CHAIN_BINARY --home $HOME_1 q block --type=height $current_block -o json | jq -r '.header.time')
echo "Last block timestamp: $block_timestamp"
block_unix_time=$(date -d "$block_timestamp" +%s)
echo "Last block UNIX time: $block_unix_time"

# check block time matches vesting period
let vesting_end_time_delta=$vesting_end_time+7
if [ $block_unix_time -lt $vesting_end_time_delta ] && [ $block_unix_time -gt $vesting_end_time ]
then
    echo "Spendable balance matches vesting end time"
else
    echo "Spendable balance does not match end time"
    exit 1
fi
