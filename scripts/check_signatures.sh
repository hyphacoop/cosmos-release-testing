#!/bin/bash
# source vars.sh

monikers=()
homes=()
api_ports=()
rpc_ports=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
    api_port=$api_prefix$i
    api_ports+=($api_port)
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
    log=$log_prefix$i
    logs+=($log)
done

signatures=$(curl -s http://localhost:${rpc_ports[0]}/block | jq -r '.result.block.last_commit.signatures')
signature_count=$(echo $signatures | jq -r '[.[] | select((.block_id_flag==2) or .block_id_flag==3)] | length')
echo "> Signature count: $signature_count"
if [ "$signature_count" = "$validator_count" ]; then
    echo "> All validators are signing"
    exit 0
else
    echo "> Not all validators are signing"
    echo "> Signatures:"
    echo $signatures | jq '.'
    echo "> Log file:"
    cat ${logs[-1]}
    exit 1
fi