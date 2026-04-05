#!/bin/bash
# Test bank module
# 1. Send
# 2. Multi-send
# 3. Send enabled params
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
  wallet=$wallet_prefix$i
  wallets+=($wallet)
done


# Query the keyring to get the sender wallet. If there is a sender wallet in the keyring, it will be used. Otherwise, a new wallet will be created.

# List keys in the keyring and check if sender wallet exists
$CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[].name' > keys.txt
if grep -q "sender" keys.txt ; then
  echo "Sender wallet already exists in keyring"
else
  echo "Creating sender wallet"
  $CHAIN_BINARY keys add sender --home $whale_home --output json | jq '.'
fi

if grep -q "grantee" keys.txt ; then
  echo "Grantee wallet already exists in keyring"
else
  echo "Creating grantee wallet"
  $CHAIN_BINARY keys add grantee --home $whale_home --output json | jq '.'
fi

sender_wallet=$($CHAIN_BINARY keys show sender --home $whale_home --output json | jq -r '.address')

echo "> Funding sender wallet"
$CHAIN_BINARY tx bank send $WALLET_1 $sender_wallet $SEND_AMOUNT$DENOM --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))

echo "> 1: Bank send"
starting_balance=$($CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
txhash=$($CHAIN_BINARY tx bank send $sender_wallet $WALLET_1 1000000$DENOM --from $sender_wallet --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was successful"
check_code $txhash
ending_balance=$($CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
diff=$(($ending_balance - $starting_balance))
if [ $diff -eq 1000000 ]; then
  echo "> PASS: tokens received"
else
  echo "> FAIL: balance difference does not equal sent amount: $diff"
  exit 1
fi

recipient1=$($CHAIN_BINARY keys show ${wallets[0]} --home ${homes[0]} --output json | jq -r '.address')
recipient2=$($CHAIN_BINARY keys show ${wallets[1]} --home ${homes[1]} --output json | jq -r '.address')
recipient3=$($CHAIN_BINARY keys show ${wallets[2]} --home ${homes[2]} --output json | jq -r '.address')

echo "> 2: Multi-send"
echo "> Create a transaction to send tokens from sender to three validator accounts using the multi-send feature"
starting_balance_1=$($CHAIN_BINARY q bank balances $recipient1 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
starting_balance_2=$($CHAIN_BINARY q bank balances $recipient2 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
starting_balance_3=$($CHAIN_BINARY q bank balances $recipient3 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
txhash=$($CHAIN_BINARY tx bank multi-send $sender_wallet $recipient1 $recipient2 $recipient3 1000000$DENOM --from $sender_wallet --home $whale_home --chain-id $CHAIN_ID -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
echo "> Checking the transaction was successful"
check_code $txhash
ending_balance_1=$($CHAIN_BINARY q bank balances $recipient1 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
ending_balance_2=$($CHAIN_BINARY q bank balances $recipient2 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
ending_balance_3=$($CHAIN_BINARY q bank balances $recipient3 --home $whale_home -o json | jq -r '.balances[] | select(.denom=="'$DENOM'").amount')
diff_1=$(($ending_balance_1 - $starting_balance_1))
diff_2=$(($ending_balance_2 - $starting_balance_2))
diff_3=$(($ending_balance_3 - $starting_balance_3))
if [ $diff_1 -eq 1000000 ] && [ $diff_2 -eq 1000000 ] && [ $diff_3 -eq 1000000 ]; then
  echo "> PASS: tokens sent with multi-send were received"
else
  echo "> FAIL: balance difference does not equal sent amount: $diff_1, $diff_2, $diff_3"
  exit 1
fi  

echo "> 3: Update bank params"
echo "> Get expedited min deposit"
expedited_min_deposit=$($CHAIN_BINARY q gov params --home $whale_home -o json | jq -r '.params.expedited_min_deposit[0].amount')
echo "> Current expedited min deposit: $expedited_min_deposit"
echo "> Updating proposal template with expedited min deposit"
jq --arg deposit "${expedited_min_deposit}uatom" '.deposit = $deposit' templates/proposal-bank-params.json > proposal-bank-params-deposit.json
jq '.' proposal-bank-params-deposit.json