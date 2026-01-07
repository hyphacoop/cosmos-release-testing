#!/bin/bash

echo "> Create test denom with $WALLET_1"
$CHAIN_BINARY tx tokenfactory create-denom test --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home | jq -r '.'
sleep $(($COMMIT_TIMEOUT*2))

$CHAIN_BINARY q tokenfactory denoms-from-admin $WALLET_1 --home $whale_home -o json | jq -r '.'

factory_denom="factory/$WALLET_1/12345678901234567890123456789012345678901234"

expected_balance="100000000"
$CHAIN_BINARY tx tokenfactory mint $expected_balance$factory_denom --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y --home $whale_home
sleep $(($COMMIT_TIMEOUT*2))
$CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r '.'

actual_balance=$($CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r --arg DENOM "$factory_denom" '.balances[] | select(.denom == $DENOM) | .amount')

if [ "$actual_balance" != "$expected_balance" ]; then
  echo "> FAIL: Expected balance $expected_balance but got $actual_balance"
  exit 1
else
  echo "> PASS: Balance is $actual_balance as expected"
fi