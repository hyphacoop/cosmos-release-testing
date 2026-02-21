#!/bin/bash
# Test creating a new denom.
subdenom=$1

check_code()
{
  txhash=$1
  echo "> Querying hash $txhash"
  code=$($CHAIN_BINARY q tx $txhash -o json --home $whale_home | jq '.code')
  if [ $code -ne 0 ]; then
    echo "> Transaction was unsuccessful."
    $CHAIN_BINARY q tx $txhash -o json --home $whale_home | jq '.'
    exit 1
  fi
}

echo "> Creating denom."
txhash=$($CHAIN_BINARY tx tokenfactory create-denom $subdenom --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
check_code $txhash

$CHAIN_BINARY q tokenfactory denoms-from-admin $WALLET_1 --home $whale_home -o json | jq -r '.'
# Verify that the denom has been created:
factory_denom="factory/$WALLET_1/$subdenom"
# Exit with code 1 if the factory denom is not found in the list of denoms from admin
if ! $CHAIN_BINARY q tokenfactory denoms-from-admin $WALLET_1 --home $whale_home -o json | jq -r --arg DENOM "$factory_denom" '.denoms[] | select(. == $DENOM)' > /dev/null; then
  echo "> FAIL: Denom $factory_denom not found in denoms from admin"
  exit 1
else
  echo "> PASS: Denom $factory_denom found in denoms from admin"
fi