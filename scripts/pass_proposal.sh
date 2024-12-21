#!/bin/bash
proposal_id=$1

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
done

echo "> Voting yes on proposal $proposal_id"
for i in $(seq 0 $[$validator_count-1])
    do
        vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from ${monikers[i]} --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home ${homes[0]} -o json"
        # echo $vote
        txhash=$($vote | jq -r .txhash)
    done
sleep $VOTING_PERIOD
sleep $[ $TIMEOUT_COMMIT+1 ]

