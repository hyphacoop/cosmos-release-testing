#!/bin/bash

sed "s%\"chain_id\": \"\"%\"chain_id\": \"$CONSUMER_CHAIN_ID\"%g" templates/create-consumer.json > create-$CONSUMER_CHAIN_ID.json
echo "> Submitting create consumer tx."

txhash=$($CHAIN_BINARY tx provider create-consumer create-$CONSUMER_CHAIN_ID.json --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --from ${WALLET_1} --home ${whale_home} -y -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT+2))

echo "Querying txhash:"
$CHAIN_BINARY q tx $txhash --home ${whale_home} -o json | jq '.'

export consumer_id=$($CHAIN_BINARY --output json q tx $txhash --home ${whale_home} | jq -r '.events[] | select(.type=="create_consumer") | .attributes[] | select(.key=="consumer_id") | .value')
echo "Consumer ID: $consumer_id"
echo "CONSUMER_ID=$consumer_id" >> $GITHUB_ENV
