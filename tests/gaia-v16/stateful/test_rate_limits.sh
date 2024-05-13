#!/bin/bash
# Test rate limits

channel_id=$1
rate_limit=$2
rpc_port=$3

echo "***** TESTING CHANNEL $channel_id RATE LIMIT: $rate_limit *****"

function test_transfer {
    send_amount=$1
    txhash=$($CHAIN_BINARY tx ibc-transfer transfer transfer $channel_id $WALLET_CONSUMER_1 $send_amount$DENOM --from $WALLET_1 --home $HOME_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json | jq -r '.txhash')
    sleep 5
    code=$(gaiad q tx $txhash -o json --home ~/.val1 | jq '.code')
    if [[ "$code" == "0" ]]; then
        echo 0 # transaction was successful
    else
        echo 1 # tx was not successful
    fi
}

echo "Bank total supply: $($CHAIN_BINARY q bank total --home $HOME_1 -o json | jq -r '.supply[0].amount')"
supply=$($CHAIN_BINARY q ratelimit rate-limit $channel_id --home $HOME_1 -o json | jq -r '.[0].flow.channel_value')
fraction=$(echo "$rate_limit" | bc)
amount=$(echo "($supply *  $fraction)/1 + 1000000" | bc )
echo "Rate limit channel value: $supply"
echo "Sending $amount..."
result=$(test_transfer $amount)
echo "test transfer result: $result"
$CONSUMER_CHAIN_BINARY q bank balances $WALLET_CONSUMER_1 --home $CONSUMER_HOME_1

if [[ "$result" == "1" ]]; then
    echo "PASS: Rate limit was detected."
else
    echo "FAIL: Rate limit was not detected."
    exit 1
fi

echo "Bank total supply: $($CHAIN_BINARY q bank total --home $HOME_1 -o json | jq -r '.supply[0].amount')"
new_supply=$($CHAIN_BINARY q ratelimit rate-limit $channel_id --home $HOME_1 -o json | jq -r '.[0].flow.channel_value')
echo "New rate limit channel value: $new_supply"
fraction=$(echo "$rate_limit / 2" | bc -l )
amount=$(echo "($supply *  $fraction)/1 + 1000000" | bc )
echo "Sending $amount..."
result=$(test_transfer $amount)
echo "test transfer result: $result"
sleep 30s
$CONSUMER_CHAIN_BINARY q bank balances $WALLET_CONSUMER_1 --home $CONSUMER_HOME_1

if [[ "$result" == "0" ]]; then
    echo "PASS: Transaction below rate limit was accepted."
else
    echo "FAIL: Transaction below rate limit was not accepted."
    exit 1
fi
