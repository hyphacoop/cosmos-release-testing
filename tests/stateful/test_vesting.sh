#!/bin/bash
vesting_time="5 minutes"
vesting_amount=100000000

# Create a vesting account with 100 atom
echo "[INFO]: > Testing vesting account with $vesting_time"
vesting_wallet1_json=$($CHAIN_BINARY --home $HOME_1 keys add vesting-1 --output json)
echo "[INFO]: feemarket_wallet1: $vesting_wallet1_json"
vesting_wallet1_addr=$(echo $vesting_wallet1_json | jq -r '.address')

vesting_end_time=$(date -d "+$vesting_time" +%s)
$CHAIN_BINARY --home $HOME_1 tx vesting create-vesting-account $vesting_wallet1_addr $vesting_amount$DENOM $vesting_end_time --from validator --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM
$CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount'


echo "[INFO]: Wait until spendable balance matches vesting amount"
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
count=0
current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')

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

timestamp=$($CHAIN_BINARY --home $HOME_1 q block --type=height $current_height -o json | jq -r '.header.time')
echo $timestamp
