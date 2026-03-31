#!/bin/bash
# Test authz module
# 1. Grant
# 2. Exec
# 3. Revoke
# 4. Expiration

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

SEND_AMOUNT=100000000
DELEGATION_AMOUNT=1000000

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


# Query the keyring to get the granter and grantee wallets. If there are granter and grantee wallets in the keyring, they will be used. Otherwise, new wallets will be created.
if $CHAIN_BINARY keys show granter --home ${homes[0]} > /dev/null  then
    echo "> Granter wallet already exists in keyring"
else
    echo "> Creating granter wallet"
    $CHAIN_BINARY keys add granter --home ${homes[0]} --output json > keys.json
    granter_wallet=$(jq -r '.address' keys.json)
    echo "> Granter wallet: $granter_wallet"
    rm keys.json
fi

if $CHAIN_BINARY keys show grantee --home ${homes[0]} > /dev/null  then
    echo "> Grantee wallet already exists in keyring"
else
    echo "> Creating grantee wallet"
    $CHAIN_BINARY keys add grantee --home ${homes[0]} --output json > keys.json
    grantee_wallet=$(jq -r '.address' keys.json)
    echo "> Grantee wallet: $grantee_wallet"
    rm keys.json
fi

# Fund the granter and grantee wallets
$CHAIN_BINARY tx bank send ${wallets[0]} $granter_wallet $SEND_AMOUNT$DENOM --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))
$CHAIN_BINARY tx bank send ${wallets[0]} $grantee_wallet $SEND_AMOUNT$DENOM --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))

echo "> 1: Granting send authorization from granter to grantee"
txhash=$($CHAIN_BINARY tx authz grant $grantee_wallet send --from granter --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the grant"
$CHAIN_BINARY q authz grants --granter $granter_wallet --grantee $grantee_wallet --home ${homes[0]} -o json | jq '.'

echo "> 2: Executing the a send message from grantee to send tokens on behalf of granter"
echo "> Create a transaction to send tokens from granter to the whale account using the grantee's authorization"
$CHAIN_BINARY tx bank send $granter_wallet $WALLET_1 1000000$DENOM --from granter --home ${homes[0]} --chain-id $CHAIN_ID --generate-only > tx.json
echo "> Transaction:"
jq '.' tx.json
echo "> Submit the bank send transaction from grantee's account using the authz exec command"
txhash=$($CHAIN_BINARY tx authz exec tx.json --from grantee --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was successful"
check_code $txhash