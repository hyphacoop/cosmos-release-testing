#!/bin/bash
# Spawn a consumer chain

homes=()
for i in $(seq -w 01 $validator_count)
do
    home=$consumer_home_prefix$i
    homes+=($home)
done

echo "> Patch create consumer message with spawn time."
jq '.' create-$CONSUMER_CHAIN_ID.json
jq '.initialization_parameters' create-$CONSUMER_CHAIN_ID.json > init_params.json
spawn_time=$(date -u --iso-8601=ns | sed s/+00:00/Z/ | sed s/,/./)
echo "> Spawn time: $spawn_time"
jq --slurpfile PARAMS init_params.json '.initialization_parameters |= $PARAMS[0]' templates/update-spawn-time.json > update-$CONSUMER_CHAIN_ID.json
jq --arg CONSUMERID "$CONSUMER_ID" '.consumer_id |= $CONSUMERID' update-$CONSUMER_CHAIN_ID.json > consumer-$CONSUMER_CHAIN_ID.json
jq -r --arg SPAWNTIME "$spawn_time" '.initialization_parameters.spawn_time |= $SPAWNTIME' consumer-$CONSUMER_CHAIN_ID.json > spawn-$CONSUMER_CHAIN_ID.json

echo "> Update consumer JSON:"
jq '.' spawn-$CONSUMER_CHAIN_ID.json
echo "> Submitting update consumer tx."
txhash=$($CHAIN_BINARY tx provider update-consumer spawn-$CONSUMER_CHAIN_ID.json --from $WALLET_1 --home $whale_home --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*3))
echo "> Update consumer tx hash: $txhash"
$CHAIN_BINARY q tx $txhash --home $whale_home -o json | jq '.'

echo "> List consumer chains"
$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq '.'
echo "> Query consumer chain"
$CHAIN_BINARY q provider consumer-chain $CONSUMER_ID --home $whale_home -o json | jq '.'

echo "> Collecting the CCV state"
$CHAIN_BINARY q provider consumer-genesis $CONSUMER_ID -o json --home $whale_home > ccv.json
jq '.' ccv.json

echo "> Patching the CCV state with the provider reward denom"
jq --arg DENOM "$CONSUMER_DENOM" '.params.reward_denoms = [$DENOM,utoken1,utoken2,atoken3]' ccv.json > ccv-reward.json
cp ccv-reward.json ccv.json

if [ "$CONSUMER_ICS" == "v4.0.0" ]; then
    if [ "$PROVIDER_ICS" == "v6.3.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        jq 'del(.params.consumer_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq '.' ccv.json
    fi
    if [ "$PROVIDER_ICS" == "v6.4.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        # $ICS_TRANSFORM_BINARY genesis transform --to "v4.x" ccv.json > ccv-consumer.json
        jq 'del(.connection_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json

        jq 'del(.params.consumer_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq '.' ccv.json
    fi
fi

if [ "$CONSUMER_ICS" == "v4.5.0" ]; then
    if [ "$PROVIDER_ICS" == "v6.4.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to "v4.5.x" ccv.json > ccv-consumer.json
        # jq 'del(.params.consumer_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq '.' ccv.json
    fi
fi

if [ "$CONSUMER_ICS" == "v5.2.0" ]; then
    if [ "$PROVIDER_ICS" == "v6.3.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        # echo "> Transform binary version:"
        # $ICS_TRANSFORM_BINARY version
        # $ICS_TRANSFORM_BINARY genesis transform ccv.json > ccv-520-1.json
        jq 'del(.params.consumer_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq '.' ccv.json
    fi
    if [ "$PROVIDER_ICS" == "v6.4.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        # echo "> Transform binary version:"
        # $ICS_TRANSFORM_BINARY version
        # $ICS_TRANSFORM_BINARY genesis transform ccv.json > ccv-520-1.json
        jq 'del(.connection_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq 'del(.params.consumer_id)' ccv.json > ccv-consumer.json
        cp ccv-consumer.json ccv.json
        jq '.' ccv.json
    fi
fi

if [ "$CONSUMER_ICS" == "v6.3.0" ]; then
    if [ "$PROVIDER_ICS" == "v6.4.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to "<v6.4.x" ccv.json > ccv-630-1.json
        cp ccv-630-1.json ccv.json
    fi
fi

echo "Patching the consumer genesis file..."
jq -s '.[0].app_state.ccvconsumer = .[1] | .[0]' $consumer_whale_home/config/genesis.json ccv.json > consumer-genesis.json
for i in $(seq 0 $[$validator_count-1])
do
    cp consumer-genesis.json ${homes[i]}/config/genesis.json
done

jq '.' consumer-genesis.json