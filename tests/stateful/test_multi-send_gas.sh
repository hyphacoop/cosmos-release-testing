#!/bin/bash
set -e

generate_wallets_count=$1
tx_amount=$2
tx_denom=$3

# Generate wallets
python scripts/generate_wallets.py $generate_wallets_count
wallets=$(jq -r '.[].address' cosmos_wallets.json | xargs)

tx_json=$($CHAIN_BINARY --home $HOME_1 tx bank multi-send $WALLET_1 $wallets $tx_amount$tx_denom --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
txhash=$(echo $tx_json | jq -r '.txhash')

echo "Query TX output:"
$CHAIN_BINARY --home $HOME_1 q tx $txhash -o json | jq '.'

code=$($CHAIN_BINARY --home $HOME_1 q tx $txhash -o json | jq '.code')
if [ $code -eq 0 ]
then
    echo "[PASS]: TX was successful"
fi
