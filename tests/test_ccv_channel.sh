#!/bin/bash
# Test Validator Set Changes

PROVIDER_ADDRESS=$(jq -r '.address' $whale_home/config/priv_validator_key.json)
CONSUMER_ADDRESS=$(jq -r '.address' $whale_home_consumer/config/priv_validator_key.json)

delegation_amount=1000000
provider_endpoint=${rpc_prefix}001
consumer_endpoint=${consumer_rpc_prefix}001

# Delegate additional stake to val 1
echo "Delegating additional stake to $VALOPER_1..."
command="$CHAIN_BINARY --home $whale_home tx staking delegate $VALOPER_1 $delegation_amount$DENOM --from $WALLET_1 --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y --chain-id $CHAIN_ID -o json"
TXHASH=$($command | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $TXHASH --home $whale_home
# Wait for consumer chain to get validator set update
echo "Waiting for the validator set update to reach the consumer chain..."
sleep $(($COMMIT_TIMEOUT*8))
# journalctl -u $PROVIDER_SERVICE_1 | tail -n 200
# journalctl -u $CONSUMER_SERVICE_1 | tail -n 200
journalctl -u $RELAYER | tail -n 200

echo "Querying provider valset:"
$CHAIN_BINARY q COMET-validator-set --home $whale_home
echo "Querying consumer valset:"
$CONSUMER_CHAIN_BINARY q tendermint-validator-set --home $whale_home_consumer
echo "Querying provider params:"
$CHAIN_BINARY q provider params --home $whale_home

PROVIDER_ADDRESS=$(jq -r '.address' $whale_home/config/priv_validator_key.json)
PROVIDER_POWER=$(curl -s http://localhost:$provider_endpoint/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_ADDRESS'") | '.voting_power'')

# Verify new voting power in consumer chain
curl http://localhost:$consumer_endpoint/validators
CONSUMER_POWER=$(curl -s http://localhost:$consumer_endpoint/validators | jq -r '.result.validators[] | select(.address=="'$CONSUMER_ADDRESS'") | '.voting_power'')

if [ -z $PROVIDER_POWER ] || [ -z $CONSUMER_POWER ]; then
    echo "Not all validator powers are available!"
    exit 1
fi

echo "Top validator VP: $PROVIDER_POWER (provider), $CONSUMER_POWER (consumer)"
if [ $PROVIDER_POWER != $CONSUMER_POWER ]; then
    echo "Consumer chain validator set does not match the provider's."
    exit 1
fi
echo "Consumer chain validator set matches the provider's."
