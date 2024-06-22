#!/bin/bash
GAS=$1
TARGET_TXS=$2

ACCOUNT=0
GAS_PRICE=0.01$DENOM
NODE_URL=http://localhost:$VAL1_RPC_PORT

# Get the current block number
current_block() {
  curl -s $NODE_URL/block | jq -r .result.block.header.height
}

# Get the size of the mempool
mempool_size() {
  curl -s $NODE_URL/num_unconfirmed_txs?limit=1 | jq -r .result.n_txs
}

# Get the size of the latest block
block_size() {
  curl -s $NODE_URL/block?height=$1 | jq -r .result.block.data.txs | jq length
}

SEQUENCE=$(curl -s http://127.0.0.1:$VAL1_API_PORT/cosmos/auth/v1beta1/accounts/$WALLET_1 | jq --raw-output ' .account.sequence')
echo "Sequence: $SEQUENCE"

# Generate unsigned tx
$CHAIN_BINARY tx bank send \
$WALLET_1 $WALLET_1 1$DENOM --from $WALLET_1 \
--account-number $ACCOUNT \
--gas $GAS --gas-prices $GAS_PRICE \
--generate-only  \
--chain-id $CHAIN_ID \
--node $NODE_URL &> unsigned.json

for (( i=0; i<$TARGET_TXS; i++ )); do
  current_mempool_size=$(mempool_size)
#   echo "Num unconfirmed txs: $current_mempool_size"

  # SIGN TX
  $CHAIN_BINARY tx sign unsigned.json --account-number $ACCOUNT --from $WALLET_1 --yes --sequence $SEQUENCE --chain-id $CHAIN_ID --offline --home $NODE_HOME &>  temp/signed.json

  # BROADCAST TX
  $CHAIN_BINARY tx broadcast signed.json --node $NODE_URL &> broadcast.log

  # If there's an account sequence mismatch, parse the expected value and use it
  if cat broadcast.log | grep -q "account sequence mismatch"; then
    SEQUENCE=$(cat broadcast.log | grep -oP 'expected \K\d+')
    echo "we had an account sequence mismatch, adjusting to $SEQUENCE"
  else
    ((SEQUENCE++))
  fi

done