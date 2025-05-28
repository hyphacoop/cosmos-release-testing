#!/bin/bash
# Test transactions with a fresh state.

SEND_AMOUNT=1000000
DELEGATION_AMOUNT=100000000

monikers=()
homes=()
rpc_ports=()
logs=()
wallets=()
operators=()
for i in $(seq -w 001 $validator_count)
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

echo "Sending funds with tx bank send..."
command="$CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} $SEND_AMOUNT$DENOM --home ${homes[0]} --from ${wallets[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json"
echo $command
TXHASH=$($command | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH

echo "Delegating funds from test account to validator..."
command="$CHAIN_BINARY tx staking delegate ${operators[0]} $DELEGATION_AMOUNT$DENOM --home ${homes[0]} --from ${wallets[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json"
echo $command
TXHASH=$($command | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH

starting_balance=$($CHAIN_BINARY q bank balances ${wallets[0]} --home ${homes[0]} -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
echo "Starting balance: $starting_balance"
echo "Waiting for rewards to accumulate..."
sleep 20
echo "Withdrawing rewards for test account..."
TXHASH=$($CHAIN_BINARY tx distribution withdraw-rewards ${operators[0]} --home ${homes[0]} --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH

ending_balance=$($CHAIN_BINARY q bank balances ${wallets[0]} --home ${homes[0]} -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
echo "Ending balance: $ending_balance"
delta=$[ $ending_balance - $starting_balance]
if [ $delta -gt 0 ]; then
    echo "$delta uatom were withdrawn successfully."
else
    echo "Rewards could not be withdrawn."
    exit 1
fi

# $CHAIN_BINARY q staking validators --home ${homes[0]}

echo "Unbonding funds from test account to validator..."
TXHASH=$($CHAIN_BINARY tx staking unbond ${operators[0]} $DELEGATION_AMOUNT$DENOM --home ${homes[0]} --from ${monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH

# $CHAIN_BINARY q staking validators --home ${homes[0]}