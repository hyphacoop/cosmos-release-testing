#!/bin/bash

echo "Registering ICA..."
$CHAIN_BINARY tx interchain-accounts controller register connection-0 --ordering ORDER_ORDERED --version "" --from $CONTROLLER_ACCT --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $CONTROLLER_HOME
sleep 60

ica_address=$($CHAIN_BINARY q interchain-accounts controller interchain-account $CONTROLLER_ACCT connection-0 --home $CONTROLLER_HOME -o json | jq -r '.address')
echo "ICA address: $ica_address"
echo "Funding ICA..."
$CHAIN_BINARY_SECONDARY tx bank send $CONTROLLER_ACCT $ica_address 100000000$DENOM --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json --home $HOST_HOME
sleep 10
