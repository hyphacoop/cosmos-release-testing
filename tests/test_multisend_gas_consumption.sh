#!/bin/bash
# Test transactions with a fresh state.

surcharge=$1

# Create space-separated list of 100 recipients, all set to WALLET_1
recipients_100=""
for i in $(seq 1 100)
do
  recipients_100="$recipients_100 $WALLET_1"
done

# Create space-separated list of 200 recipients, all set to WALLET_1
recipients_200=""
for i in $(seq 1 200)
do
  recipients_200="$recipients_200 $WALLET_1"
done

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


## MULTISEND: 100 recipients
echo "> Sending funds with tx bank multi-send"
command="$CHAIN_BINARY tx bank multi-send $WALLET_1 $recipients_100 1$DENOM --home $whale_home --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json"
echo $command
TXHASH=$($command | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH
# Collect gas consumed from the transaction and check that it is within expected range
gas_consumed=$(($CHAIN_BINARY q tx $TXHASH -o json --home $whale_home | jq -r '.gas_used'))

echo "> Gas consumed for multi-send with 100 recipients: $gas_consumed"

expected_max_gas=250000
if [ "$surcharge" == "surcharge" ]; then
  expected_max_gas=$((300 * 10000))
fi

if [ $gas_consumed -gt $expected_max_gas ]; then
    echo "> FAIL: Gas consumed for multi-send with 100 recipients is greater than $expected_max_gas"
    exit 1
  else
    echo "> PASS: Gas consumed for multi-send with 100 recipients is less than or equal to $expected_max_gas"
fi

## MULTISEND: 200 recipients
echo "> Sending funds with tx bank multi-send"
command="$CHAIN_BINARY tx bank multi-send $WALLET_1 $recipients_200 1$DENOM --home $whale_home --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json"
echo $command
TXHASH=$($command | jq -r '.txhash')
echo "Tx hash: $TXHASH"
sleep $(($COMMIT_TIMEOUT+2))
check_code $TXHASH
# Collect gas consumed from the transaction and check that it is within expected range
gas_consumed=$(($CHAIN_BINARY q tx $TXHASH -o json --home $whale_home | jq -r '.gas_used'))

expected_max_gas=500000
if [ "$surcharge" == "surcharge" ]; then
  expected_max_gas=$((300 * 40000))
fi

if [ $gas_consumed -gt $expected_max_gas ]; then
    echo "> FAIL: Gas consumed for multi-send with 200 recipients is greater than $expected_max_gas"
    exit 1
  else
    echo "> PASS: Gas consumed for multi-send with 200 recipients is less than or equal to $expected_max_gas"
fi
