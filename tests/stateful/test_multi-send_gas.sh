#!/bin/bash
set -e

generate_wallets_count=$1
tx_amount=$2
tx_denom=$3

# Generate wallets
python scripts/generate_wallets.py $generate_wallets_count
wallets=$(jq -r '.[].address' cosmos_wallets.json | xargs)

echo "Sending tx..."
tx_json=$($CHAIN_BINARY --home $HOME_1 tx bank multi-send $WALLET_1 $wallets $tx_amount$tx_denom --from val --gas auto --gas-adjustment 5 --gas-prices 3000uatom -y -o json)
txhash=$(echo $tx_json | jq -r '.txhash')

# wait for tx block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

set +e
tx_query=$($CHAIN_BINARY --home $HOME_1 q tx $txhash -o json)
if [ $? -ne 0 ]
then
    echo "[ERROR]: TX Failed, TX JSON output:"
    echo "$tx_json" | jq -r '.'
    exit 1
fi
set -e

code=$(echo $tx_query | jq -r '.code')
if [ $code -eq 0 ]
then
    echo "[PASS]: TX was successful"
fi

# Query gas wanted
tx_gas_wanted=$(echo $tx_query | jq -r '.gas_wanted')

# Query gas used
tx_gas_used=$(echo $tx_query | jq -r '.gas_used')

echo "Gas wanted: $tx_gas_wanted"
echo "Gas used: $tx_gas_used"
