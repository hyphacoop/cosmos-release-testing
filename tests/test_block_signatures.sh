#!/bin/bash 
# Check that blocks are being produced.

host=$1
port=$2
expected=$3

# Check how many validators are signing blocks
signatures=$(curl -s http://$host:$port/block | jq '.result.block.last_commit.signatures')
signature_count=$(echo $signatures | jq '[select(.block_id_flag==2)] | length')
echo "> Signature count: $signature_count"
if [ "$signature_count" != "$3" ]; then
    echo "> Not all validators are signing blocks."
    echo "$signatures"
    exit 1
else
    echo "> All validators are signing blocks."
fi