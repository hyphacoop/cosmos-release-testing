#!/bin/bash

preload_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Pre-load price: $preload_price$DENOM"

echo "Loading mempool with large gas txs from fee market wallets..."
count=0
while [ $count -lt 3 ]
do
    echo "[DEBUG]: Large txs count $count"
    export WALLET=$FEE_MARKET_WALLET1 ACCOUNT_NUMBER=$FEE_MARKET_1_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET2 ACCOUNT_NUMBER=$FEE_MARKET_2_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET3 ACCOUNT_NUMBER=$FEE_MARKET_3_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET4 ACCOUNT_NUMBER=$FEE_MARKET_4_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET5 ACCOUNT_NUMBER=$FEE_MARKET_5_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET6 ACCOUNT_NUMBER=$FEE_MARKET_6_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET7 ACCOUNT_NUMBER=$FEE_MARKET_7_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET8 ACCOUNT_NUMBER=$FEE_MARKET_8_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET9 ACCOUNT_NUMBER=$FEE_MARKET_9_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    export WALLET=$FEE_MARKET_WALLET10 ACCOUNT_NUMBER=$FEE_MARKET_10_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 20000000 2 0.005
    let count=$count+1
done

echo "Loading mempool with txs from fee market wallets..."
# scripts/stateful/gaia-v18/load_blocks.sh 100000 5000 0.01
count=0
while [ $count -lt 500 ]
do
    echo "[DEBUG]: txs count $count"
    export WALLET=$FEE_MARKET_WALLET1 ACCOUNT_NUMBER=$FEE_MARKET_1_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET2 ACCOUNT_NUMBER=$FEE_MARKET_2_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET3 ACCOUNT_NUMBER=$FEE_MARKET_3_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET4 ACCOUNT_NUMBER=$FEE_MARKET_4_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET5 ACCOUNT_NUMBER=$FEE_MARKET_5_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET6 ACCOUNT_NUMBER=$FEE_MARKET_6_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET7 ACCOUNT_NUMBER=$FEE_MARKET_7_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET8 ACCOUNT_NUMBER=$FEE_MARKET_8_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET9 ACCOUNT_NUMBER=$FEE_MARKET_9_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    export WALLET=$FEE_MARKET_WALLET10 ACCOUNT_NUMBER=$FEE_MARKET_10_ACCOUNT_NUMBER; scripts/stateful/gaia-v18/load_blocks.sh 100000 2 0.005
    let count=$count+1
done

echo "Waiting for blocks to get loaded..."
num_unconfirmed_txs=$(curl -s http://localhost:$VAL1_RPC_PORT/num_unconfirmed_txs | jq -r '.result.n_txs')
echo "Unconfirmed txs: $num_unconfirmed_txs"
while [ $num_unconfirmed_txs -gt "1000" ] ; do
    echo "Sleeping for a minute..."
    sleep 1m
    num_unconfirmed_txs=$(curl -s http://localhost:$VAL1_RPC_PORT/num_unconfirmed_txs | jq -r '.result.n_txs')
    echo "Unconfirmed txs: $num_unconfirmed_txs"
done
echo "Less than 1000 txs remain in the mempool"

current_price=$($CHAIN_BINARY q feemarket gas-prices --home $HOME_1 -o json | jq -r '.prices[0].amount')
echo "Current gas price: $current_price$DENOM"
if (( $(echo "$current_price > $preload_price" | bc -l) )); then
    echo "PASS: Current price is greater than pre-load price."
else
    echo "FAIL: Current price is not greater than pre-load price."
    exit 1
fi