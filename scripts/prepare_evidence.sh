#!/bin/bash

evidence_filename=$1
echo "***** EVIDENCE JSON MODIFICATION *****"
echo "> Evidence filename: $evidence_filename"

echo "> Cast vote a height as integer."
jq '.vote_a.height |= tonumber' $evidence_filename > evidence-mod.json
mv evidence-mod.json $evidence_filename

echo "> Cast vote b height as integer."
jq '.vote_b.height |= tonumber' $evidence_filename > evidence-mod.json
mv evidence-mod.json $evidence_filename

# echo "> Base64 encode vote a block id hash."
# jq -r '.vote_a.block_id.hash' $evidence_filename
# hash=$(jq -r '.vote_a.block_id.hash' $evidence_filename | xxd -r -p | base64)
# echo "Hash: >$hash<"
# jq --arg HASH "$hash" '.vote_a.block_id.hash |= $HASH' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Base64 encode vote a block id part hash."
# jq -r '.vote_a.block_id.parts.hash' $evidence_filename
# hash=$(jq -r '.vote_a.block_id.parts.hash' $evidence_filename | xxd -r -p | base64)
# echo "Hash: >$hash<"
# jq --arg HASH "$hash" '.vote_a.block_id.parts.hash |= $HASH' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Base64 encode vote b block id hash."
# hash=$(jq -r '.vote_b.block_id.hash' $evidence_filename | xxd -r -p | base64)
# echo "Hash: >$hash<"
# jq --arg HASH "$hash" '.vote_b.block_id.hash |= $HASH' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Base64 encode vote b block id part hash."
# hash=$(jq -r '.vote_b.block_id.parts.hash' $evidence_filename | xxd -r -p | base64)
# echo "Hash: >$hash<"
# jq --arg HASH "$hash" '.vote_b.block_id.parts.hash |= $HASH' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Rename vote_a parts key."
# jq '.vote_a.block_id.parts as $p | .vote_a.block_id.part_set_header = $p | del(.vote_a.block_id.parts)' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Rename vote_b parts key."
# jq '.vote_b.block_id.parts as $p | .vote_b.block_id.part_set_header = $p | del(.vote_b.block_id.parts)' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename
# jq '.' $evidence_filename

# echo "> Base64 encode vote_a val address."
# addr=$(jq -r '.vote_a.validator_address' $evidence_filename | xxd -r -p | base64)
# echo "Base64-encoded: $addr"
# jq --arg ADDR "$addr" '.vote_a.validator_address |= $ADDR' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Base64 encode vote_b val address."
# addr=$(jq -r '.vote_b.validator_address' $evidence_filename | xxd -r -p | base64)
# echo "Base64-encoded: $addr"
# jq --arg ADDR "$addr" '.vote_b.validator_address |= $ADDR' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Rename total voting power."
# jq '.TotalVotingPower as $p | .total_voting_power = $p | del(.TotalVotingPower)' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Rename validator power key."
# jq '.ValidatorPower as $p | .validator_power = $p | del(.ValidatorPower)' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

# echo "> Rename timestamp key."
# jq '.Timestamp as $p | .timestamp = $p | del(.Timestamp)' $evidence_filename > evidence-mod.json
# mv evidence-mod.json $evidence_filename

echo "> Cast total voting power as integer."
jq '.total_voting_power |= tonumber' $evidence_filename > evidence-mod.json
mv evidence-mod.json $evidence_filename

echo "> Cast validator power as integer."
jq '.validator_power |= tonumber' $evidence_filename > evidence-mod.json
mv evidence-mod.json $evidence_filename

jq '.' $evidence_filename

echo "***** EVIDENCE JSON MODIFICATION ENDS *****"
