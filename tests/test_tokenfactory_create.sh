#!/bin/bash
# Test creating a new denom.
subdenom=$1

check_code()
{
  txhash=$1
  echo "Querying hash $txhash..."
  code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_1 | jq '.code')
  if [ $code -ne 0 ]; then
    echo "tx was unsuccessful."
    $CHAIN_BINARY q tx $txhash -o json --home $HOME_1 | jq '.'
    exit 1
  fi
}

echo "> Creating denom."
txhash=$($CHAIN_BINARY tx tokenfactory create-denom $subdenom --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
check_code $txhash

$CHAIN_BINARY q tokenfactory denoms-from-admin $WALLET_1 --home $whale_home -o json | jq -r '.'
