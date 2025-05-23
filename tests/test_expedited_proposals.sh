#!/bin/bash 


echo "> Staking params:"
$CHAIN_BINARY q staking params --output json --home $HOME_1 | jq '.'
value_pre_change=$($CHAIN_BINARY q staking params --output json --home $HOME_1 | jq -r '.params.max_validators')
echo "> Updating staking params via expedited proposal."

max_validators=50
jq --argjson MAXVALS $max_validators '.messages[0].params.max_validators=$MAXVALS' templates/proposal-staking-params.json > staking-params.json
jq '.' staking-params.json

jq '.expedited=true' staking-params.json > expedited.json
jq '.' expedited.json

echo "> Passing proposal."
scripts/param_change.sh expedited.json
echo "> Staking params:"
$CHAIN_BINARY q staking params --output json --home $HOME_1 | jq '.'
value_post_change=$($CHAIN_BINARY q staking params --output json --home $HOME_1 | jq -r '.params.max_validators')
echo "> Started at $value_pre_change, ended at $value_post_change"
if [[ "$value_post_change" != "$value_pre_change" ]]; then
    echo "PASS: Expedited proposal was executed."
else
    echo "FAIL: Expedited proposal was not executed."
    exit 1
fi

echo ">Gov params:"
$CHAIN_BINARY q gov params --output json --home $HOME_1 | jq '.'
value_pre_change=$($CHAIN_BINARY q gov params --output json --home $HOME_1 | jq -r '.params.quorum')
new_quorum=0.4

$CHAIN_BINARY q gov params --output json --home $HOME_1 > params.json
echo "params.json:"
cat params.json
jq --rawfile PARAMS params.json '.messages[0].params = $PARAMS' templates/proposal-gov-params.json > gov-params.json
jq '.' gov-params.json

# params=$($CHAIN_BINARY q gov params --output json --home $HOME_1 | jq '.params')
# echo "params: $params"
# jq --argjson PARAMS $params '.messages[0].params = $PARAMS' templates/proposal-gov-params.json > gov-params.json
# jq '.' gov-params.json

jq --arg QUORUM "$new_quorum" '.messages[0].params.quorum=$QUORUM' gov-params.json > gov-params-quorum.json
jq '.' gov-params-quorum.json
jq '.expedited=true' gov-params-quorum.json > expedited.json
jq '.' expedited.json

echo "> Passing proposal."
scripts/param_change.sh expedited.json
echo "> Gov params:"
$CHAIN_BINARY q gov params --output json --home $HOME_1 | jq '.'
value_post_change=$($CHAIN_BINARY q gov params --output json --home $HOME_1 | jq -r '.params.quorum')
echo "> Started at $value_pre_change, ended at $value_post_change"
if [[ "$value_post_change" != "$value_pre_change" ]]; then
    echo "PASS: Expedited proposal was executed."
else
    echo "FAIL: Expedited proposal was not executed."
    exit 1
fi