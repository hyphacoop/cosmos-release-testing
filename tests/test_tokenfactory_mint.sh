#!/bin/bash
# Test minting a denom.
subdenom=$1
amount=$2

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

# Get the pre-mint balance for the factory denom
factory_denom="factory/$WALLET_1/$subdenom"

balance_before=$($CHAIN_BINARY q bank balances $WALLET_1 --home $HOME_1 -o json | jq -r --arg DENOM "$factory_denom" '.balances[] | select(.denom == $DENOM) | .amount')
# Set to 0 if the denom is not found in the balances
if [ -z "$balance_before" ]; then
  balance_before=0
fi
echo "> Balance before minting: $balance_before"

echo "> Minting denom."
txhash=$($CHAIN_BINARY tx tokenfactory mint $amount$factory_denom --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json --home $whale_home | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
check_code $txhash

balance_after=$($CHAIN_BINARY q bank balances $WALLET_1 --home $whale_home -o json | jq -r --arg DENOM "$factory_denom" '.balances[] | select(.denom == $DENOM) | .amount')
echo "> Balance after minting: $balance_after"
# Exit with code 1 if the balance after is not greater than the balance before
if [ "$balance_after" -le "$balance_before" ]; then
  echo "> FAIL: Balance after minting ($balance_after) is not greater than balance before minting ($balance_before)"
  exit 1
else
  echo "> PASS: Balance after minting ($balance_after) is greater than balance before minting ($balance_before)"
fi

