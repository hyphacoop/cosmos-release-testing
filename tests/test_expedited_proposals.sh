#!/bin/bash 


echo "> Staking params:"
$CHAIN_BINARY q staking params --output json | jq '.'
echo "> Updating staking params via expedited proposal."

max_validators=50
jq --argjson MAXVALS $max_validators '.messages[0].params.max_validators=$MAXVALS' templates/proposal-staking-params.json > staking-params.json
jq '.' staking-params.json

jq --argjson MAXVALS $max_validators '.expedited=true' staking-params.json > expedited.json
jq '.' expedited.json

echo "> Passing proposal."
scripts/param_change.sh expedited.json
echo "> Staking params:"
$CHAIN_BINARY q staking params --output json | jq '.'
