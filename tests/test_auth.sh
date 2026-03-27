#!/bin/bash
# Test auth module
# - Params update: 

SEND_AMOUNT=1000000
DELEGATION_AMOUNT=100000000

monikers=()
homes=()
rpc_ports=()
logs=()
wallets=()
operators=()
for i in $(seq -w $COUNT_WIDTH $validator_count)
do
  moniker=$moniker_prefix$i
  monikers+=($moniker)
  home=$home_prefix$i
  homes+=($home)
  rpc_port=$rpc_prefix$i
  rpc_ports+=($rpc_port)
  log=$log_prefix$i
  logs+=($log)
done

$CHAIN_BINARY keys list --output json --home ${homes[0]} > keys.json
jq '.' keys.json
for i in $(seq 0 $[$validator_count-1])
do
    wallet=$(jq -r --arg MONIKER "${monikers[i]}" '.[] | select(.name==$MONIKER).address' keys.json)
    wallets+=($wallet)
    echo "> Wallet: $wallet"
    echo "> Command: $CHAIN_BINARY debug bech32-convert --prefix cosmosvaloper $wallet"
    operator=$($CHAIN_BINARY debug bech32-convert --prefix cosmosvaloper $wallet)
    operators+=($operator)
    echo "> Wallet: $wallet | operator: $operator"
done
rm keys.json

check_code()
{
  txhash=$1
  echo "Querying hash $txhash..."
  code=$($CHAIN_BINARY q tx $txhash -o json --home ${homes[0]} | jq '.code')
  if [ $code -ne 0 ]; then
    echo "tx was unsuccessful."
    $CHAIN_BINARY q tx $txhash -o json --home ${homes[0]} | jq '.'
    exit 1
  fi
}

## AUTH: PARAMS
echo "> Test auth params"
$CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq '.'
memo_limit=$($CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq -r '.params.max_memo_characters')
echo "> Test memo characters limit"
MEMO=$(head -c $memo_limit /dev/urandom | base64)
echo "> Sending tx with $memo_limit character memo (should succeed)"
$CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} $SEND_AMOUNT --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.'

MEMO=$(head -c $(( memo_limit +1 )) /dev/urandom | base64)
echo "> Sending tx with $(( memo_limit +1 )) character memo (should fail)"
$CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} $SEND_AMOUNT --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.'