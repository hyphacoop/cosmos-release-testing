#!/bin/bash

consumer_monikers=()
consumer_homes=()
consumer_api_ports=()
consumer_rpc_ports=()
consumer_p2p_ports=()
consumer_grpc_ports=()
consumer_pprof_ports=()
consumer_logs=()

consumer_monikers_lc=()
consumer_homes_lc=()
consumer_api_ports_lc=()
consumer_rpc_ports_lc=()
consumer_p2p_ports_lc=()
consumer_grpc_ports_lc=()
consumer_pprof_ports_lc=()
consumer_logs_lc=()
for i in $(seq -w 01 $[$validator_count-1])
do
    consumer_moniker=$consumer_moniker_prefix$i
    consumer_monikers+=($consumer_moniker)
    consumer_home=$consumer_home_prefix$i
    consumer_homes+=($consumer_home)
    consumer_api_port=$consumer_api_prefix$i
    consumer_api_ports+=($consumer_api_port)
    consumer_rpc_port=$consumer_rpc_prefix$i
    consumer_rpc_ports+=($consumer_rpc_port)
    consumer_p2p_port=$consumer_p2p_prefix$i
    consumer_p2p_ports+=($consumer_p2p_port)
    consumer_grpc_port=$consumer_grpc_prefix$i
    consumer_grpc_ports+=($consumer_grpc_port)
    consumer_pprof_port=$consumer_pprof_prefix$i
    consumer_pprof_ports+=($consumer_pprof_port)
    consumer_log=$consumer_log_prefix$i
    consumer_logs+=($consumer_log)

    consumer_moniker_lc=$consumer_moniker_prefix_lc$i
    consumer_monikers_lc+=($consumer_moniker_lc)
    consumer_home_lc=$consumer_home_prefix_lc$i
    consumer_homes_lc+=($consumer_home_lc)
    consumer_api_port_lc=$consumer_api_prefix_lc$i
    consumer_api_ports_lc+=($consumer_api_port_lc)
    consumer_rpc_port_lc=$consumer_rpc_prefix_lc$i
    consumer_rpc_ports_lc+=($consumer_rpc_port_lc)
    consumer_p2p_port_lc=$consumer_p2p_prefix_lc$i
    consumer_p2p_ports_lc+=($consumer_p2p_port_lc)
    consumer_grpc_port_lc=$consumer_grpc_prefix_lc$i
    consumer_grpc_ports_lc+=($consumer_grpc_port_lc)
    consumer_pprof_port_lc=$consumer_pprof_prefix_lc$i
    consumer_pprof_ports_lc+=($consumer_pprof_port_lc)
    consumer_log_lc=$consumer_log_prefix_lc$i
    consumer_logs_lc+=($consumer_log_lc)
done

echo "> 0. Get trusted height using provider consensus state."
client_id=$($CHAIN_BINARY q provider list-consumer-chains -o json --home $whale_home | jq -r --arg chain "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id==$chain).client_id')
echo "> Client ID: $client_id"
TRUSTED_HEIGHT=$($CHAIN_BINARY q ibc client consensus-state-heights $client_id --home $whale_home -o json | jq -r '.consensus_state_heights[-1].revision_height')
echo "> Trusted height: $TRUSTED_HEIGHT"


for (( i=0; i<$validator_count-1; i++ ))
do
    session=${consumer_monikers[i]}
    echo "> Stopping session: $session"
    tmux send-keys -t $session C-c
    cp -r ${consumer_homes[i]} ${consumer_homes_lc[i]}
    echo "> Adjust ports"
    $CONSUMER_CHAIN_BINARY config node tcp://localhost:${consumer_rpc_ports_lc[i]} --home ${consumer_homes_lc[i]}
    toml set --toml-path ${consumer_homes_lc[i]}/config/app.toml api.address "tcp://0.0.0.0:${consumer_api_ports_lc[i]}"
    toml set --toml-path ${consumer_homes_lc[i]}/config/app.toml grpc.address "0.0.0.0:${consumer_grpc_ports_lc[i]}"
    toml set --toml-path ${consumer_homes_lc[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${consumer_rpc_ports_lc[i]}"
    toml set --toml-path ${consumer_homes_lc[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${consumer_pprof_ports_lc[i]}"
    toml set --toml-path ${consumer_homes_lc[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${consumer_p2p_ports_lc[i]}"
    echo "{}" > ${consumer_homes_lc[i]}/config/addrbook.json
done

whale_peer_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes_lc[0]})
whale_peeer="$peer_a_id@127.0.0.1:${consumer_p2p_ports_lc[0]}"

for (( i=1; i<$validator_count-1; i++ ))
do
    toml set --toml-path ${consumer_homes_lc[i]}/config/config.toml p2p.persistent_peers "$whale_peer"
done

echo "> Restarting original and secondary chain"
for (( i=0; i<$validator_count-1; i++ ))
do
    tmux new-session -d -s ${consumer_monikers[i]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[i]} 2>&1 | tee ${consumer_logs[i]}"
    tmux new-session -d -s ${consumer_monikers_lc[i]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes_lc[i]} 2>&1 | tee ${consumer_logs_lc[i]}"
done

sleep 10
echo "> Original chain:"
tail ${consumer_logs[0]} -n 50
echo "> Duplicate chain:"
tail ${consumer_logs_lc[0]} -n 50

echo "> Keys in LC consumer:"
$CONSUMER_CHAIN_BINARY keys list --home ${consumer_homes_lc[0]} --keyring-backend test
echo "> Submit bank send on LC consumer"
$CONSUMER_CHAIN_BINARY tx bank send $RECIPIENT $($CONSUMER_CHAIN_BINARY keys list --home ${consumer_homes_lc[0]} --keyring-backend test --output json | jq -r '.[1].address') 1000$CONSUMER_DENOM --from ${consumer_monikers[0]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${consumer_homes_lc[0]} -y
sleep 30

echo "> Get current height header from main consumer"
$CONSUMER_CHAIN_BINARY status --home ${consumer_homes[0]}
OG_HEIGHT=$($CONSUMER_CHAIN_BINARY status --home ${consumer_homes[0]} | jq -r '.SyncInfo.latest_block_height')
echo "Height: $OG_HEIGHT"
sleep 5
echo "> Get IBC header from main consumer:"
OG_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $OG_HEIGHT --home ${consumer_homes[0]} -o json)
echo "> Get IBC header from second consumer:"
LC_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $OG_HEIGHT --home ${consumer_homes_lc[0]} -o json)

echo "> IBC header at trusted height + 1 from main consumer:"
TRUSTED_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $(($TRUSTED_HEIGHT +1)) --home ${consumer_homes[0]} -o json)

echo "> Fill trusted valset and height"
TRUSTED_VALS=$(echo $TRUSTED_HEADER | jq -r '.validator_set')
OG_HEADER=$(echo $OG_HEADER | jq --argjson vals "$TRUSTED_VALS" '.trusted_validators = $vals')
LC_HEADER=$(echo $LC_HEADER | jq --argjson vals "$TRUSTED_VALS" '.trusted_validators = $vals')

OG_HEADER=$(echo $OG_HEADER | jq --arg height $TRUSTED_HEIGHT '.trusted_height.revision_height = $height')
LC_HEADER=$(echo $LC_HEADER | jq --arg height $TRUSTED_HEIGHT '.trusted_height.revision_height = $height')

tee lc_misbehaviour.json<<EOF
{
    "client_id": "$client_id",
    "header_1": $OG_HEADER,
    "header_2": $LC_HEADER
}
EOF

jq '.' lc_misbehaviour.json

echo "> Submit misbehaviour to provider"
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chainid "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chainid).consumer_id')
$CHAIN_BINARY tx provider submit-consumer-misbehaviour $CONSUMER_ID lc_misbehaviour.json --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y 
sleep $(($COMMIT_TIMEOUT*3))

echo "> Client $client_id status:"
$CHAIN_BINARY q ibc client status $client_id --home $whale_home
echo "> Client $client_id state:"
$CHAIN_BINARY q ibc client state $client_id -o json --home $whale_home | jq '.'
echo "> Client $client_id state frozen height:"
$CHAIN_BINARY q ibc client state $client_id -o json --home $whale_home | jq -r '.client_state.frozen_height'

echo "> Signing infos:"
$CHAIN_BINARY q slashing signing-infos --home $whale_home -o json | jq '.'
exit 0

echo "> Opt in with new validator."
consumer_pubkey=$($CONSUMER_CHAIN_BINARY tendermint show-validator --home ${consumer_homes[-2]})
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chainid "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chainid).consumer_id')
echo "> Consumer id: $consumer_id, pubkey: $consumer_pubkey"
$CHAIN_BINARY tx provider opt-in $consumer_id $consumer_pubkey --from $eqwallet --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[-1]} -y
sleep $(($COMMIT_TIMEOUT*3))

echo "> Copy snapshot from whale"
session=${consumer_monikers[0]}
echo "> Session: $session"
tmux send-keys -t $session C-c
cp ${consumer_homes[-2]}/data/priv_validator_state.json ./state.bak

cp -r ${consumer_homes[0]}/data ${consumer_homes[-2]}/
cp -r ${consumer_homes[0]}/data ${consumer_homes[-1]}/
cp ./state.bak ${consumer_homes[-2]}/data/priv_validator_state.json
cp ./state.bak ${consumer_homes[-1]}/data/priv_validator_state.json
cp ${consumer_homes[0]}/config/genesis.json ${consumer_homes[-2]}/config/genesis.json
cp ${consumer_homes[0]}/config/genesis.json ${consumer_homes[-1]}/config/genesis.json

echo "> Duplicate validator key"
cp ${consumer_homes[-2]}/config/priv_validator_key.json ${consumer_homes[-1]}/config/priv_validator_key.json


tmux new-session -d -s ${consumer_monikers[-2]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-2]} 2>&1 | tee ${consumer_logs[-2]}"
tmux new-session -d -s ${consumer_monikers[-1]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-1]} 2>&1 | tee ${consumer_logs[-1]}"
sleep 60
tmux new-session -d -s $session "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[0]} 2>&1 | tee ${consumer_logs[0]}"
sleep 90
echo "> Whale node:"
tail ${consumer_logs[0]} -n 50
echo "> Node A (${consumer_monikers[-2]}):"
tail ${consumer_logs[-2]} -n 50
echo "> Node B (${consumer_monikers[-1]}):"
tail ${consumer_logs[-1]} -n 50

echo "> Consumer:"
$CONSUMER_CHAIN_BINARY q slashing signing-infos --home ${consumer_whale_home}
echo "> Provider:"
$CHAIN_BINARY q slashing signing-infos --home ${whale_home}

consensus_address=$($CONSUMER_CHAIN_BINARY tendermint show-address --home ${consumer_homes[-2]})
echo "> Consumer consensus address: $consensus_address"
validator_check=$($CONSUMER_CHAIN_BINARY q evidence --home $consumer_whale_home -o json | jq '.' | grep $consensus_address)
echo $validator_check
if [ -z "$validator_check" ]; then
  echo "No equivocation evidence found."
  exit 1
else
  echo "Equivocation evidence found!"
fi
echo "> Collecting infraction height."
height=$($CONSUMER_CHAIN_BINARY q evidence --home $consumer_whale_home -o json | jq -r '.evidence[0].height')
echo "> Evidence height: $height"

echo "> Collecting evidence around the infraction height in consumer chain."
evidence_block=$(($height+2))
$CONSUMER_CHAIN_BINARY q block $evidence_block --home $consumer_whale_home
$CONSUMER_CHAIN_BINARY q block $evidence_block --home $consumer_whale_home | jq '.block.evidence.evidence[0].value' > evidence.json
jq '.' evidence.json
scripts/prepare_evidence.sh evidence.json

echo "> Collecting IBC header at infraction height in consumer chain."
$CONSUMER_CHAIN_BINARY q ibc client header --height $height --home $consumer_whale_home -o json | jq '.' > ibc-header.json
echo "> IBC header JSON:"
jq '.' ibc-header.json
scripts/prepare_infraction_header.sh ibc-header.json

echo "> Submitting double voting evidence tx"
$CHAIN_BINARY tx provider submit-consumer-double-voting $consumer_id evidence.json ibc-header.json --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Provider:"
address=$($CHAIN_BINARY comet show-address --home ${homes[-1]})
echo "> Address: $address"
$CHAIN_BINARY q slashing signing-infos --home ${whale_home} -o json | jq '.'
tombstoned=$($CHAIN_BINARY q slashing signing-infos --home ${whale_home} -o json | jq -r --arg addr "$address" '.info[] | select(.address==$addr).tombstoned')
echo "> Tombstoned: $tombstoned"
tmux send-keys -t ${consumer_monikers[-1]} C-c
tmux send-keys -t ${consumer_monikers[-2]} C-c
tmux send-keys -t ${monikes[-1]} C-c
rm -r ${consumer_homes[-2]}
rm -r ${consumer_homes[-1]}
rm -r ${homes[-1]}

if [[ "$tombstoned" == "true" ]]; then
    echo "> PASS: Validator has been tombstoned."
else
    echo "> FAIL: Validator has not been tombstoned."
    exit 1
fi
