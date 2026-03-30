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
MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit)) )
echo "> Generated memo: $MEMO (${#MEMO} characters)"

echo "> Sending tx with ${#MEMO} character memo (should succeed)"
txhash=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.txhash')
sleep $((COMMIT_TIMEOUT*2))
check_code $txhash

MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit + 1)) )
echo "> Generated memo: $MEMO (${#MEMO} characters)"
echo "> Sending tx with ${#MEMO} character memo (should fail)"
response=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.')
sleep $((COMMIT_TIMEOUT*2))
echo "> Response: $response"
if [[ $response == *"memo too large"* ]]; then
  echo "> Error message indicates memo character limit was exceeded, as expected."
else
  echo "> Unexpected error message. Test failed."
  exit 1
fi

echo "> Test auth params update"
echo "> Setting memo characters limit to 100"
echo "> Setting current params to the auth_params variable"
auth_params=$($CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq '.params')
echo "> Current auth params: $auth_params"
new_auth_params=$(echo $auth_params | jq '.max_memo_characters = 100')
echo "> New auth params: $new_auth_params"
echo "> Setting new auth params in proposal template"
jq --argjson new_auth_params "$new_auth_params" '.messages[].params = $new_auth_params' templates/proposal-auth-params.json > proposal-auth-params.json
echo "> Submitting proposal to update auth params"
txhash=$($CHAIN_BINARY tx gov submit-proposal proposal-auth-params.json --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
$CHAIN_BINARY q gov proposals --home $whale_home -o json | jq -r '.proposals[-1]'
echo "> Checking proposal id"
proposal_id=$($CHAIN_BINARY q gov proposals --home ${homes[0]} -o json | jq -r '.proposals[-1].id')
echo "> Voting for the proposal"
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))
sleep $VOTING_PERIOD
echo "> Checking if the proposal passed"
$CHAIN_BINARY q gov proposals --home ${homes[0]} -o json | jq -r '.proposals[-1]'
echo "> Checking if the auth params were updated"
$CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq '.'

$CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq '.'
memo_limit=$($CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq -r '.params.max_memo_characters')

echo "> Test memo characters limit"
MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit)) )
echo "> Generated memo: $MEMO (${#MEMO} characters)"
echo "> Sending tx with ${#MEMO} character memo (should succeed)"
txhash=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.txhash')
sleep $((COMMIT_TIMEOUT*2))
check_code $txhash

MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit + 1)) ) 
echo "> Generated memo: $MEMO (${#MEMO} characters)"
echo "> Sending tx with ${#MEMO} character memo (should fail)"
response=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.')
sleep $((COMMIT_TIMEOUT*2))
echo "> Response: $response"
if [[ $response == *"memo too large"* ]]; then
  echo "> Error message indicates memo character limit was exceeded, as expected."
else
  echo "> Unexpected error message. Test failed."
  exit 1
fi

echo "> Restoring starting auth params"
echo "> Setting new auth params in proposal template"
jq --argjson new_auth_params "$auth_params" '.messages[].params = $new_auth_params' templates/proposal-auth-params.json > proposal-auth-params.json
echo "> Submitting proposal to update auth params"
txhash=$($CHAIN_BINARY tx gov submit-proposal proposal-auth-params.json --from $WALLET_1 --home $whale_home --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq -r '.txhash')
sleep $((COMMIT_TIMEOUT*2))
$CHAIN_BINARY q gov proposals --home $whale_home -o json | jq -r '.proposals[-1]'
echo "> Checking proposal id"
proposal_id=$($CHAIN_BINARY q gov proposals --home ${homes[0]} -o json | jq -r '.proposals[-1].id')
echo "> Voting for the proposal"
$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y -o json | jq '.'
sleep $((COMMIT_TIMEOUT*2))
sleep $VOTING_PERIOD
echo "> Checking if the proposal passed"
$CHAIN_BINARY q gov proposals --home ${homes[0]} -o json | jq -r '.proposals[-1]'
echo "> Checking if the auth params were updated"
$CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq '.'
memo_limit=$($CHAIN_BINARY q auth params --home ${homes[0]} -o json | jq -r '.params.max_memo_characters')

echo "> Test memo characters limit"
MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit)) ) 
echo "> Generated memo: $MEMO (${#MEMO} characters)"

echo "> Sending tx with ${#MEMO} character memo (should succeed)"
txhash=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.txhash')
sleep $((COMMIT_TIMEOUT*2))
check_code $txhash
MEMO=$(openssl rand -hex 256 | cut -c1-$((memo_limit + 1)) ) 
echo "> Generated memo: $MEMO (${#MEMO} characters)"
echo "> Sending tx with ${#MEMO} character memo (should fail)"
response=$($CHAIN_BINARY tx bank send ${wallets[0]} ${wallets[1]} 1uatom --from $WALLET_1 --home ${homes[0]} --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --note "$MEMO" -y -o json | jq '.')
sleep $((COMMIT_TIMEOUT*2))
echo "> Response: $response"
if [[ $response == *"memo too large"* ]]; then
  echo "> Error message indicates memo character limit was exceeded, as expected."
else
  echo "> Unexpected error message. Test failed."
  exit 1
fi
