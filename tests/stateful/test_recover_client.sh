#!/bin/bash
# Test IBC client recovery
client_id=$1
recovery_chan_id=$2
recovery_tokens=100000000
gas_tokens=1000000
tx_amount=1000000

set -e

echo "[INFO]: Creating new wallet on stateful chain..."
test_wallet1_json=$($CHAIN_BINARY --home $CHAIN_HOME keys add stateful-recovery-wallet --output json)
test_wallet1_addr=$(echo $test_wallet1_json | jq -r '.address')
echo "test_wallet1_addr: $test_wallet1_addr"

echo "[INFO]: Creating new wallet on recovery chain..."
recovery_wallet1_json=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME keys add recovery-wallet --output json)
recovery_wallet1_addr=$(echo $recovery_wallet1_json | jq -r '.address')
echo "recovery_wallet1_addr: $recovery_wallet1_addr"

echo "[INFO]: Get client params"
client_max_clock_drift=$($CHAIN_BINARY --home $CHAIN_HOME q ibc client state $client_id -o json | jq -r '.client_state.max_clock_drift')
client_trusting_period=$($CHAIN_BINARY --home $CHAIN_HOME q ibc client state $client_id -o json | jq -r '.client_state.trusting_period')
echo "$client_id max clock drift: $client_max_clock_drift"
echo "$client_id trusting period: $client_trusting_period"

echo "[INFO]: Send tokens to recovery chain..."
$CHAIN_BINARY --home $CHAIN_HOME tx ibc-transfer transfer transfer $recovery_chan_id $recovery_wallet1_addr $recovery_tokens$DENOM --from $MONIKER_1 --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y

echo "[INFO]: Wait for 5 blocks..."
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Check tokens in recovery chain..."
recovery_wallet_denom=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r  '.balances[0].denom')
recovery_wallet_amount=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r  '.balances[0].amount')
$CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr
echo "Recovery wallet denom: $recovery_wallet_denom"
echo "Recovery wallet amount: $recovery_wallet_amount"

if [ "$recovery_wallet_amount" != "$recovery_tokens" ]
then
    echo "[ERROR]: Tokens amount $recovery_wallet_amount did not match $recovery_tokens"
    exit 1
else
    echo "[PASS]: Tokens amount $recovery_wallet_amount matches $recovery_tokens"
fi

echo "[INFO]: Send tokens for gas on recovery chain..."
$CHAIN_BINARY tx bank send $WALLET_1 $recovery_wallet1_addr $gas_tokens$DENOM --home $SECONDARY_CHAIN_HOME --from $MONIKER_1 --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y

echo "[INFO]: Wait for 1 block..."
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Check tokens in recovery chain..."
recovery_current_uatom=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
recovery_current_ibc=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$recovery_wallet_denom\") | .amount")
echo "$recovery_current_uatom$DENOM"
echo "$recovery_current_ibc$recovery_wallet_denom"

echo "[INFO]: Send IBC tokens back..."
$CHAIN_BINARY --home $SECONDARY_CHAIN_HOME tx ibc-transfer transfer transfer channel-0 $test_wallet1_addr $tx_amount$recovery_wallet_denom --from recovery-wallet --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Check tokens in stateful chain..."
stateful_current_uatom=$($CHAIN_BINARY --home $CHAIN_HOME q bank balances $test_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
echo "$stateful_current_uatom$DENOM"
if [ "$stateful_current_uatom" != "$tx_amount" ]
then
    echo "[ERROR]: Tokens amount $stateful_current_uatom on stateful chain did not match $tx_amount"
    exit 1
else
    echo "[PASS]: Tokens amount $stateful_current_uatom on stateful chain matches $tx_amount"
fi

echo "[INFO]: Stopping hermes..."
screen -XS hermes.service quit || true
killall hermes || true
sleep 1

echo "[INFO]: Waiting for $client_id to expire..."
current_client_status=$($CHAIN_BINARY --home $CHAIN_HOME q ibc client status $client_id -o json | jq -r '.status')
while [ $current_client_status == "Active" ]
do
    current_client_status=$($CHAIN_BINARY --home $CHAIN_HOME q ibc client status $client_id -o json | jq -r '.status')
    echo "Client $client_id status: $current_client_status"
    sleep 60
done

echo "[INFO]: Creating a substitute client..."
hermes_output=$(hermes create client --host-chain $CHAIN_ID --reference-chain $SECONDARY_CHAIN_ID --trusting-period 300s --clock-drift 50s)
echo $hermes_output
substitute_client_id=$(echo $hermes_output | grep -oh "\07-tendermint-\w*")
echo "[INFO]: substitute client ID: $substitute_client_id"

echo "[INFO]: Creating proposal file..."
jq -r --arg subject_client_id "$client_id" --arg substitute_client_id "$substitute_client_id" '.messages[0].subject_client_id=$subject_client_id | .messages[0].substitute_client_id=$substitute_client_id' templates/proposal-recover-client.json > proposal-recover-client.json
jq -r '.' proposal-recover-client.json

echo "[INFO]: Submitting recover proposal..."
scripts/submit_proposal.sh proposal-recover-client.json

echo "[INFO]: Starting hermes service..."
screen -L -Logfile $HOME/artifact/hermes.service.log -S hermes.service -d -m bash $HOME/hermes.service.sh

echo "[INFO]: Check if $client_id is active again..."
current_client_status=$($CHAIN_BINARY --home $CHAIN_HOME q ibc client status $client_id -o json | jq -r '.status')
echo "Client $client_id status: $current_client_status"
if [ "$current_client_status" != "Active" ]
then
    echo "[ERROR]: Client $client_id is NOT Active"
    exit 1
else
    echo "[PASS]: Client $client_id is Active"
fi

echo "[INFO] Post recovery tests..."
echo "[INFO]: Check tokens in recovery chain..."
recovery_current_uatom=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
recovery_current_ibc=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$recovery_wallet_denom\") | .amount")
echo "$recovery_current_uatom$DENOM"
echo "$recovery_current_ibc$recovery_wallet_denom"

echo "[INFO]: Send tokens to recovery chain..."
$CHAIN_BINARY --home $CHAIN_HOME tx ibc-transfer transfer transfer $recovery_chan_id $recovery_wallet1_addr $tx_amount$DENOM --from $MONIKER_1 --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Check if IBC tokens matches expected value..."
let expected_recovery_tokens=$recovery_current_ibc+tx_amount
echo "Expected tokens $expected_recovery_tokens$recovery_wallet_denom in recovery chain wallet"
recovery_current_ibc=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$recovery_wallet_denom\") | .amount")
echo "Current IBC tokens in recovery chain wallet $recovery_current_ibc$recovery_wallet_denom"

if [ "$recovery_current_ibc" != "$expected_recovery_tokens" ]
then
    echo "Recovery chain wallet have $recovery_current_ibc IBC tokens, does not match expected value of $expected_recovery_tokens"
    exit 1
else
    echo "Recovery chain wallet have $recovery_current_ibc IBC tokens, matches expected value of $expected_recovery_tokens"
fi

echo "[INFO]: Send IBC tokens back to stateful chain..."
$CHAIN_BINARY --home $SECONDARY_CHAIN_HOME tx ibc-transfer transfer transfer channel-0 $test_wallet1_addr $tx_amount$recovery_wallet_denom --from recovery-wallet --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Check if tokens matches expected value on recovery chain..."
let expected_recovery_tokens=$recovery_current_ibc-tx_amount
echo "Expected tokens $expected_recovery_tokens$recovery_wallet_denom in recovery chain wallet"
recovery_current_ibc=$($CHAIN_BINARY --home $SECONDARY_CHAIN_HOME q bank balances $recovery_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$recovery_wallet_denom\") | .amount")
echo "Current IBC tokens in recovery chain wallet $recovery_current_ibc$recovery_wallet_denom"

if [ "$recovery_current_ibc" != "$expected_recovery_tokens" ]
then
    echo "Recovery chain wallet have $recovery_current_ibc IBC tokens, does not match expected value of $expected_recovery_tokens"
    exit 1
else
    echo "Recovery chain wallet have $recovery_current_ibc IBC tokens, matches expected value of $expected_recovery_tokens"
fi

echo "[INFO]: Check tokens in stateful chain..."
let expected_tokens=$stateful_current_uatom+$tx_amount
stateful_current_uatom=$($CHAIN_BINARY --home $CHAIN_HOME q bank balances $test_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
echo "$stateful_current_uatom$DENOM"
if [ "$stateful_current_uatom" != "$expected_tokens" ]
then
    echo "[ERROR]: Tokens amount $stateful_current_uatom on stateful chain did not match $expected_tokens"
    exit 1
else
    echo "[PASS]: Tokens amount $stateful_current_uatom on stateful chain matches $expected_tokens"
fi
