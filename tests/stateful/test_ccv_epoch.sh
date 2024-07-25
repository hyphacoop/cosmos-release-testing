#!/bin/bash
# Test Validator Set Changes
epoch=$1

# Get VP before test
PROVIDER_BADDRESS=$(jq -r '.address' $HOME_1/config/priv_validator_key.json)
PROVIDER_POWER_START=$(curl -s http://localhost:$VAL1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')
# Verify new voting power in consumer chain
CONSUMER_POWER_START=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')
echo "[INFO] Starting Top validator VP: $PROVIDER_POWER_START (provider), $CONSUMER_POWER_START (consumer)"

# Delegate additional stake to val 1
echo "[INFO] Delegating additional stake to $MONIKER_1..."
$CHAIN_BINARY --home $HOME_1 tx staking delegate $VALOPER_1 $DELEGATE_2_AMOUNT$DENOM --from $MONIKER_2 --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -b sync -y --chain-id $CHAIN_ID
# Wait for consumer chain to get validator set update
echo "Waiting for the validator set update to reach the consumer chain..."
sleep 60
PROVIDER_POWER=$(curl -s http://localhost:$VAL1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')

echo "[INFO] Starting provider voting power: $PROVIDER_POWER_START"
echo "[INFO] Current provider voting power: $PROVIDER_POWER"
if [ $PROVIDER_POWER -eq $PROVIDER_POWER_START ]
then
    echo "[ERROR] Provider voting power didn't update!!!"
    exit 4
fi

# Verify new voting power in consumer chain
CONSUMER_POWER=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')

# Wait 60 more seconds if VP stll the same
if [ $PROVIDER_POWER == $PROVIDER_POWER_START ]; then
    echo "[WARNING] VP is the same as starting value, we will wait 60 seconds more"
    sleep 60
    PROVIDER_POWER=$(curl -s http://localhost:$VAL1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')
fi
if [ $PROVIDER_POWER == $PROVIDER_POWER_START ]; then
    echo "[ERROR] VP is still the same as starting value!"
    exit 3
fi

# Check if both chains VP matches before the epoch
echo "Top validator VP: $PROVIDER_POWER (provider), $CONSUMER_POWER (consumer)"
if [ $PROVIDER_POWER == $CONSUMER_POWER ]; then
    echo "[ERROR] Consumer chain validator set match the provider's before the epoch."
    exit 1
fi

# Wait for epoch block
echo "[INFO] Waiting for $epoch blocks for epoch"
tests/test_block_production.sh localhost $CON1_RPC_PORT $epoch 120

# Get VP on both chains after epoch
PROVIDER_POWER=$(curl -s http://localhost:$VAL1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')
CONSUMER_POWER=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.validators[] | select(.address=="'$PROVIDER_BADDRESS'") | '.voting_power'')
echo "[INFO] Top validator VP: $PROVIDER_POWER (provider), $CONSUMER_POWER (consumer)"

# Check if both chain matches
if [ $PROVIDER_POWER != $CONSUMER_POWER ]; then
    echo "[ERROR] Consumer chain validator set does not match the provider's."
    exit 2
fi
echo "[INFO] Consumer chain validator set matches the provider's."
