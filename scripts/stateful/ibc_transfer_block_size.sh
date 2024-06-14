#!/bin/bash
BLOCK_SIZE=$1

PAYLOAD_LENGTH=$(echo "$BLOCK_SIZE / 40" | bc -l)
PAYLOAD_LENGTH=${PAYLOAD_LENGTH%.*}
MEMO_SIZE=$PAYLOAD_LENGTH
RECIPIENT_SIZE=$PAYLOAD_LENGTH
BATCH_SIZE=10
echo "Memo size: $MEMO_SIZE"
echo "Recv size: $RECIPIENT_SIZE"

CHAIN_BINARY=gaiad-test
ADDRESS=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
CHANNEL=channel-0
DENOM=uatom
ACCOUNT=0
GAS=2500000
GAS_PRICE=0.005$DENOM
CHAIN_ID=testnet
NODE_URL=http://localhost:27001
NODE_HOME=/root/.val1

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

# SUBMIT BATCH OF IBC TRANSFERS
SEQUENCE=$(curl -s http://127.0.0.1:25001/cosmos/auth/v1beta1/accounts/$ADDRESS | jq --raw-output ' .account.sequence')

while true; do
  last_block=$(current_block)
  last_block_size=$(block_size $last_block)
  current_mempool_size=$(mempool_size)
  echo "Last block size: $last_block_size"

  # Send transactions in a batch
  for ((i=0; i<$BATCH_SIZE; i++)); do

    # GENERATE TX
    $CHAIN_BINARY tx ibc-transfer transfer transfer \
    $CHANNEL $(openssl rand -hex $RECIPIENT_SIZE) 1$DENOM --from $ADDRESS \
    --account-number $ACCOUNT \
    --memo $(openssl rand -hex $MEMO_SIZE) \
    --gas $GAS --gas-prices $GAS_PRICE \
    --generate-only  \
    --chain-id $CHAIN_ID \
    --node $NODE_URL &> temp/unsigned.json

    # SIGN TX
    $CHAIN_BINARY tx sign temp/unsigned.json --account-number $ACCOUNT --from $ADDRESS --yes --sequence $SEQUENCE --chain-id $CHAIN_ID --offline --home $NODE_HOME &>  temp/signed.json

    # BROADCAST TX
    $CHAIN_BINARY tx broadcast temp/signed.json --node $NODE_URL &> temp/broadcast.log

    # If there's an account sequence mismatch, parse the expected value and use it
    if cat temp/broadcast.log | grep -q "account sequence mismatch"; then
      SEQUENCE=$(cat temp/broadcast.log | grep -oP 'expected \K\d+')
      echo "we had an account sequence mismatch, adjusting to $SEQUENCE"
    else
      ((SEQUENCE++))
    fi

  done
  # Check for a new block before looping again
  while [[ $(current_block) -le $last_block ]]; do
    continue
  done
done