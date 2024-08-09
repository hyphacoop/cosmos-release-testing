#!/bin/bash
TX_GAS=$1
TARGET_TXS=$2
PRICE="$3$DENOM"
ACCOUNT=$ACCOUNT_NUMBER
NODE_URL=http://localhost:$VAL1_RPC_PORT

echo "Price: $PRICE"
# Get the size of the mempool
mempool_size() {
  curl -s $NODE_URL/num_unconfirmed_txs?limit=1 | jq -r .result.n_txs
}

echo "[INFO] Account Number: $ACCOUNT"
echo "[INFO] Wallet: $WALLET"
SEQUENCE=$(curl -s http://127.0.0.1:$VAL1_API_PORT/cosmos/auth/v1beta1/accounts/$WALLET | jq --raw-output ' .account.sequence')
echo "[INFO] Sequence: $SEQUENCE"

# Generate unsigned tx
$CHAIN_BINARY tx bank send \
$WALLET $WALLET 1$DENOM --from $WALLET \
--account-number $ACCOUNT \
--gas $TX_GAS --gas-prices $PRICE \
--generate-only  \
--chain-id $CHAIN_ID \
--node $NODE_URL &> unsigned.json

for (( i=0; i<$TARGET_TXS; i++ )); do
  current_mempool_size=$(mempool_size)
  echo "Num unconfirmed txs: $current_mempool_size"

  # SIGN TX
  # $CHAIN_BINARY tx sign unsigned.json --account-number $ACCOUNT --from $WALLET --yes --sequence $SEQUENCE --chain-id $CHAIN_ID --offline --home $HOME_1 &>  signed.json
  $CHAIN_BINARY tx sign unsigned.json --account-number $ACCOUNT --from $WALLET --yes --sequence $SEQUENCE --chain-id $CHAIN_ID --offline --home $HOME_1 --output-document signed.json
  # BROADCAST TX
  $CHAIN_BINARY tx broadcast signed.json --node $NODE_URL &> broadcast.log
  # If there's an account sequence mismatch, parse the expected value and use it
  if cat broadcast.log | grep -q "account sequence mismatch"; then
    SEQUENCE=$(cat broadcast.log | grep -oP 'expected \K\d+')
    echo "we had an account sequence mismatch, adjusting to $SEQUENCE"
  else
    ((SEQUENCE++))
  fi
  # echo "Unsigned JSON:"
  # cat unsigned.json
  # echo "Signed JSON:"
  # cat signed.json
  echo "[INFO] Broadcast tx log:"
  cat broadcast.log
done

# jq '.' unsigned.json
# jq '.' signed.json
# cat broadcast.log