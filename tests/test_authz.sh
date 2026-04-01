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

# List keys in the keyring and check if granter and grantee wallets exist
$CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[].name' > keys.txt
if grep -q "granter" keys.txt ; then
  echo "Granter wallet already exists in keyring"
else
  echo "Creating granter wallet"
  $CHAIN_BINARY keys add granter --home $whale_home --output json | jq '.'
fi

if grep -q "grantee" keys.txt ; then
  echo "Grantee wallet already exists in keyring"
else
  echo "Creating grantee wallet"
  $CHAIN_BINARY keys add grantee --home $whale_home --output json | jq '.'
fi

granter_wallet=$($CHAIN_BINARY keys show granter --home $whale_home --output json | jq -r '.address')
grantee_wallet=$($CHAIN_BINARY keys show grantee --home $whale_home --output json | jq -r '.address')


# Fund the granter and grantee wallets
$CHAIN_BINARY tx bank send $WALLET_1 $granter_wallet $SEND_AMOUNT$DENOM --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))
$CHAIN_BINARY tx bank send $WALLET_1 $grantee_wallet $SEND_AMOUNT$DENOM --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))

echo "> 1: Granting send authorization from granter to grantee"
txhash=$($CHAIN_BINARY tx authz grant $grantee_wallet send --spend-limit 100000000uatom --from granter --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the grant"
$CHAIN_BINARY q authz grants --granter $granter_wallet --grantee $grantee_wallet --home $whale_home -o json | jq '.'

echo "> 2: Executing the a send message from grantee to send tokens on behalf of granter"
echo "> Create a transaction to send tokens from granter to the whale account using the grantee's authorization"
$CHAIN_BINARY tx bank send $granter_wallet $WALLET_1 1000000$DENOM --from granter --home $whale_home --chain-id $CHAIN_ID --generate-only > tx.json
echo "> Transaction:"
jq '.' tx.json
echo "> Submit the bank send transaction from grantee's account using the authz exec command"
txhash=$($CHAIN_BINARY tx authz exec tx.json --from grantee --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was successful"
check_code $txhash

echo "> 3: Revoking the send authorization from granter to grantee"
txhash=$($CHAIN_BINARY tx authz revoke $grantee_wallet send --from granter --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the grant was revoked"
$CHAIN_BINARY q authz grants --granter $granter_wallet --grantee $grantee_wallet --home $whale_home -o json | jq '.'
echo "> Submit the bank send transaction from grantee's account using the authz exec command"
txhash=$($CHAIN_BINARY tx authz exec tx.json --from grantee --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was not successful"
check_code $txhash

echo "> 1b: Granting send authorization with expiration from granter to grantee"
# Set expiration to 1 minute from now in Unix timestamp format
current_time=$(date +%s)
expiration=$(date -d "+1 minute" +%s)
echo "> Current time: $current_time, expiration time: $expiration"
txhash=$($CHAIN_BINARY tx authz grant $grantee_wallet send --spend-limit 100000000uatom --from granter --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json --expiration $expiration | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the grant"
$CHAIN_BINARY q authz grants --granter $granter_wallet --grantee $grantee_wallet --home $whale_home -o json | jq '.'

echo "> 2b: Executing the a send message from grantee to send tokens on behalf of granter before expiration"
echo "> Create a transaction to send tokens from granter to the whale account using the grantee's authorization"
$CHAIN_BINARY tx bank send $granter_wallet $WALLET_1 1000000$DENOM --from granter --home $whale_home --chain-id $CHAIN_ID --generate-only > tx.json
echo "> Transaction:"
jq '.' tx.json
echo "> Submit the bank send transaction from grantee's account using the authz exec command"
txhash=$($CHAIN_BINARY tx authz exec tx.json --from grantee --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was successful"
check_code $txhash

echo "> 4: Checking the send authorization expires after 1 minute"
echo "> Waiting for 1 minute for the grant to expire"
sleep 1m
echo "> Submit the bank send transaction from grantee's account using the authz exec command"
txhash=$($CHAIN_BINARY tx authz exec tx.json --from grantee --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was not successful"
check_code $txhash