#!/bin/bash

echo "> Create test denom with $WALLET_1"
$CHAIN_BINARY tx tokenfactory create-denom test --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home | jq -r '.'
sleep $(($COMMIT_TIMEOUT*2))

$CHAIN_BINARY q tokenfactory denoms-from-admin $WALLET_1 --home $whale_home -o json | jq -r '.'

factory_denom="factory/$WALLET_1/test"

$CHAIN_BINARY tx tokenfactory mint 100000000$factory_denom --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y --home $whale_home
sleep $(($COMMIT_TIMEOUT*2))
$CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r '.'