#!/bin/bash
# Test rate limits

channel_id=$1
rate_limit=$2
rpc_port=$3

echo "***** TESTING CHANNEL $channel_id RATE LIMIT: $rate_limit *****"

function test_transfer {
    send_amount=$1
    txhash=$($CHAIN_BINARY tx ibc-transfer transfer transfer $channel_id $WALLET_1 $send_amount$DENOM --from $WALLET_1 --home $HOME_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json | jq -r '.txhash')
    sleep 3
    code=$(gaiad q tx $txhash -o json --home ~/.val1 | jq '.code')
    if [[ "$code" == "0" ]]; then
        echo 0 # transaction was successful
    else
        echo 1 # tx was not successful
    fi
}

# supply=$($CHAIN_BINARY q bank total --home $HOME_1 -o json | jq -r '.supply[0].amount')
supply=$($CHAIN_BINARY q ratelimit rate-limit $channel_id --home $HOME_1 -o json | jq -r '.[0].flow.channel_value')
fraction=$(echo "$rate_limit" | bc)
amount=$(echo "($supply *  $fraction)/1 " | bc )
echo "uatom supply: $supply"
echo "Sending $amount..."
result=$(test_transfer $amount)
if [[ "$result" == "1" ]]; then
    echo "PASS: Rate limit was detected."
else
    echo "FAIL: Rate limit was not detected."
    sleep 10
    $CHAIN_BINARY q bank balances $WALLET_1 --node http://localhost:$rpc_port
    exit 1
fi

fraction=$(echo "$rate_limit / 2" | bc -l )
amount=$(echo "($supply *  $fraction)/1 + 1" | bc )
echo "Sending $amount..."
result=$(test_transfer $amount)
echo "test transfer result: $result"
if [[ "$result" == "0" ]]; then
    echo "PASS: Transaction below rate limit was accepted."
    sleep 10
    $CHAIN_BINARY q bank balances $WALLET_1 --node http://localhost:$rpc_port
else
    echo "FAIL: Transaction below rate limit was not accepted."
    exit 1
fi

echo "Sending $amount..."
result=$(test_transfer $amount)
echo "test transfer result: $result"
if [[ "$result" == "0" ]]; then
    echo "PASS: Transaction below rate limit was accepted."
    sleep 10
    $CHAIN_BINARY q bank balances $WALLET_1 --node http://localhost:$rpc_port
else
    echo "FAIL: Transaction below rate limit was not accepted."
    exit 1
fi

echo "Sending $amount..."
result=$(test_transfer $amount)
echo "test transfer result: $result"
if [[ "$result" == "1" ]]; then
    echo "PASS: Rate limit was detected."
else
    echo "FAIL: Rate limit was not detected."
    sleep 10
    $CHAIN_BINARY q bank balances $WALLET_1 --node http://localhost:$rpc_port
    exit 1
fi