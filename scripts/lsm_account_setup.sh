#!/bin/bash
# set -x
source scripts/process_tx.sh

funding=250000000

$CHAIN_BINARY keys add happy_bonding --home $whale_home
$CHAIN_BINARY keys add happy_liquid_1 --home $whale_home
$CHAIN_BINARY keys add happy_liquid_2 --home $whale_home
$CHAIN_BINARY keys add happy_liquid_3 --home $whale_home
$CHAIN_BINARY keys add happy_owner --home $whale_home

happy_bonding=$($CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[] | select(.name=="happy_bonding").address')
happy_liquid_1=$($CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[] | select(.name=="happy_liquid_1").address')
happy_liquid_2=$($CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[] | select(.name=="happy_liquid_2").address')
happy_liquid_3=$($CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[] | select(.name=="happy_liquid_3").address')
happy_owner=$($CHAIN_BINARY keys list --home $whale_home --output json | jq -r '.[] | select(.name=="happy_owner").address')

echo > "Funding bonding and tokenizing accounts."
submit_tx "tx bank send $WALLET_1 $happy_bonding  $funding$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $whale_home
submit_tx "tx bank send $WALLET_1 $happy_liquid_1 $funding$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $whale_home
submit_tx "tx bank send $WALLET_1 $happy_liquid_2 $funding$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $whale_home
submit_tx "tx bank send $WALLET_1 $happy_liquid_3 $funding$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $whale_home
submit_tx "tx bank send $WALLET_1 $happy_owner    $funding$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $whale_home
