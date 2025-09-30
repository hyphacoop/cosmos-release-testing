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

echo "[INFO]: Send tokens for gas on recovery chain"
$CHAIN_BINARY tx bank send $WALLET_1 $recovery_wallet_amount $gas_tokens$DENOM --home $CHAIN_HOME --from $MONIKER_1 --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y

echo "[INFO]: Wait for 1 block..."
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Check tokens in recovery chain..."
recovery_current_uatom=$($CHAIN_BINARY --home .recovery-chain q bank balances cosmos1y96dngzpnr6pna3lea8mmuq0vllz38dfdrw5zx -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
recovery_current_ibc=$($CHAIN_BINARY --home .recovery-chain q bank balances cosmos1y96dngzpnr6pna3lea8mmuq0vllz38dfdrw5zx -o json | jq -r ".balances[] | select(.denom==\"$recovery_wallet_denom\") | .amount")
echo "$recovery_current_uatom$DENOM"
echo "$recovery_current_ibc$recovery_wallet_denom$"

echo "[INFO]: Send IBC tokens back..."
$CHAIN_BINARY --home .recovery-chain tx ibc-transfer transfer transfer channel-0 $test_wallet1_addr $tx_amount$recovery_wallet_denom --from recovery-wallet --gas $GAS --gas-prices $GAS_PRICES$DENOM --gas-adjustment  $GAS_ADJUSTMENT -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10

echo "[INFO]: Check tokens in stateful chain..."
stateful_current_uatom=$($CHAIN_BINARY --home .recovery-chain q bank balances cosmos1y96dngzpnr6pna3lea8mmuq0vllz38dfdrw5zx -o json | jq -r ".balances[] | select(.denom==\"$DENOM\") | .amount")
echo "$stateful_current_uatom$DENOM"

# echo "[INFO]: Stopping hermes..."
# screen -XS hermes.service quit || true
# killall hermes || true
# sleep 1

# echo "[INFO]: Waiting for $client_id to expire..."
# current_client_status=$(go/bin/gaiad --home .val1 q ibc client status $client_id -o json | jq -r '.status')
# while [ $current_client_status == "Active" ]
# do
#     current_client_status=$(go/bin/gaiad --home .val1 q ibc client status $client_id -o json | jq -r '.status')
#     echo "Client $client_id status: $current_client_status"
#     sleep 60
# done
