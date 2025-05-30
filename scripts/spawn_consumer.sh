#!/bin/bash
# Spawn a consumer chain

monikers=()
homes=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
done

echo "> Patch create consumer message with spawn time."
jq '.' create-$CONSUMER_CHAIN_ID.json
init_params=$(jq '.initialization_parameters' create-$CONSUMER_CHAIN_ID.json)
echo "> Init params: $init_params"
echo $init_params | jq '.'
spawn_time=$(date -u --iso-8601=ns | sed s/+00:00/Z/ | sed s/,/./)
jq --argjson PARAMS $init_params '.initialization_parameters |= $PARAMS' templates/update-spawn-time.json > update-$CONSUMER_CHAIN_ID.json
jq --arg CONSUMERID "$CONSUMER_ID" '.consumer_id |= $CONSUMERID' update-$CONSUMER_CHAIN_ID.json > consumer-$CONSUMER_CHAIN_ID.json
jq -r --arg SPAWNTIME "$spawn_time" '.spawn_time |= $SPAWNTIME' consumer-$CONSUMER_CHAIN_ID.json > spawn-$CONSUMER_CHAIN_ID.json

echo "> Submitting update consumer tx."
$CHAIN_BINARY tx provider update-consumer spawn-$CONSUMER_CHAIN_ID.json --from ${monikers[0]} --home ${homes[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y
sleep $(($COMMIT_TIMEOUT+2))
echo "> List consumer chains"
$CHAIN_BINARY q provider list-consumer-chains --home ${homes[0]} -o json | jq '.'
echo "> Query consumer chain"
$CHAIN_BINARY q provider consumer-chain $CONSUMER_ID --home ${homes[0]} -o json | jq '.'

exit 0
# client_id=$($CHAIN_BINARY q provider list-consumer-chains --home $HOME_1 -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).client_id')
# echo "Client ID: $client_id"
# $CHAIN_BINARY q provider  consumer-id-from-client-id $client_id
# consumer_id=$($CHAIN_BINARY q provider  consumer-id-from-client-id $client_id)
echo "Consumer ID: $CONSUMER_ID"

echo "Collecting the CCV state..."
$CHAIN_BINARY q provider consumer-genesis $CONSUMER_ID -o json --home $HOME_1 > ccv.json
# jq '.params |= . + {"soft_opt_out_threshold": "0.10"}' ccv-pre.json > ccv-optout.json

jq '.' ccv.json

echo "Patching the CCV state with the provider reward denom"
jq --arg DENOM "$CONSUMER_DENOM" '.params.reward_denoms = [$DENOM]' ccv.json > ccv-reward.json
cp ccv-reward.json ccv.json

if [ "$CONSUMER_ICS" == "v3.3.0" ]; then
    if [ "$PROVIDER_ICS" == "v4.0.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to v3.3.x ccv.json > ccv-330-1.json
        cp ccv-330-1.json ccv.json
    elif [ "$PROVIDER_ICS" == "v4.1.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to v3.3.x ccv.json > ccv-330-1.json
        cp ccv-330-1.json ccv.json
    elif [ "$PROVIDER_ICS" == "v4.1.1" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to v3.3.x ccv.json > ccv-330-1.json
        cp ccv-330-1.json ccv.json
    elif [ "$PROVIDER_ICS" == "v4.2.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to v3.3.x ccv.json > ccv-330-1.json
        cp ccv-330-1.json ccv.json
    fi
fi

if [ "$CONSUMER_ICS" == "v4.0.0" ]; then
    if [ "$PROVIDER_ICS" == "v3.3.0" ]; then
        echo "Patching for ICS compatibility: Provider $PROVIDER_ICS | Consumer $CONSUMER_ICS"
        $ICS_TRANSFORM_BINARY genesis transform --to v4.x ccv.json > ccv-400-1.json
        cp ccv-400-1.json ccv.json
    fi
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
jq -s '.[0].app_state.ccvconsumer = .[1] | .[0]' $CONSUMER_HOME_1/config/genesis.json ccv.json > consumer-genesis.json
cp consumer-genesis.json $CONSUMER_HOME_1/config/genesis.json
cp consumer-genesis.json $CONSUMER_HOME_2/config/genesis.json
cp consumer-genesis.json $CONSUMER_HOME_3/config/genesis.json
