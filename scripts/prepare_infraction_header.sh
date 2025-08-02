#!/bin/bash

header_filename=$1
echo "***** IBC HEADER JSON MODIFICATION BEGINS *****"

echo "> Cast header height to integer."
jq '.signed_header.header.height |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Cast commit height to integer."
jq '.signed_header.commit.height |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Replace BLOCK_ID_FLAG_COMMIT with 2."
sed "s%\"BLOCK_ID_FLAG_COMMIT\"%2%g" $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Replace BLOCK_ID_FLAG_NIL with 3."
sed "s%\"BLOCK_ID_FLAG_NIL\"%3%g" $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Cast validators' voting power to integer."
jq '.validator_set.validators[].voting_power |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Cast validators' proposer priority to integer."
jq '.validator_set.validators[].proposer_priority |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Cast proposer's voting power to integer."
jq '.validator_set.proposer.voting_power |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Cast proposer's proposer priority to integer."
jq '.validator_set.proposer.proposer_priority |= tonumber' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Remove total_voting_power."
jq 'del(.validator_set.total_voting_power)' $header_filename > header-mod.json
mv header-mod.json $header_filename

echo "> Remove revision_number."
jq 'del(.trusted_height.revision_number)' $header_filename > header-mod.json
mv header-mod.json $header_filename

jq '.' $header_filename

echo "***** IBC HEADER JSON MODIFICATION ENDS *****"
