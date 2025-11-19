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

homes=()
for i in $(seq -w 01 $[$validator_count-1])
do
    home=$home_prefix$i
    homes+=($home)

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
    toml set --toml-path ${consumer_homes_lc[i]}/config/client.toml node "http://127.0.0.1:${consumer_rpc_ports_lc[i]}"
    echo "{}" > ${consumer_homes_lc[i]}/config/addrbook.json
done

whale_peer_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes_lc[0]})
whale_peer="$whale_peer_id@127.0.0.1:${consumer_p2p_ports_lc[0]}"

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
sleep $(($COMMIT_TIMEOUT*10))
echo "> Original chain:"
tail ${consumer_logs[0]} -n 50
echo "> Duplicate chain (node 1):"
tail ${consumer_logs_lc[0]} -n 50

echo "> Submit bank send on LC consumer"
$CONSUMER_CHAIN_BINARY tx bank send $RECIPIENT $($CONSUMER_CHAIN_BINARY keys list --home ${consumer_homes_lc[0]} --keyring-backend test --output json | jq -r '.[1].address') 1000$CONSUMER_DENOM --from ${consumer_monikers[0]} --home ${consumer_homes_lc[0]} --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $CONSUMER_GAS_PRICE -y
sleep $(($COMMIT_TIMEOUT*10))

echo "> Get current height header from main consumer"
$CONSUMER_CHAIN_BINARY status --home ${consumer_homes[0]}
OG_HEIGHT=$($CONSUMER_CHAIN_BINARY status --home ${consumer_homes[0]} | jq -r '.SyncInfo.latest_block_height')
echo "Height: $OG_HEIGHT"
sleep $(($COMMIT_TIMEOUT*10))
echo "> Get IBC header from main consumer"
OG_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $OG_HEIGHT --home ${consumer_homes[0]} -o json)
echo "> Get IBC header from second consumer"
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
echo "> Consumer chain: $CONSUMER_CHAIN_ID"
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chainid "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chainid).consumer_id')
echo "> Consumer ID: $consumer_id"
$CHAIN_BINARY tx provider submit-consumer-misbehaviour $consumer_id lc_misbehaviour.json --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y 
sleep $(($COMMIT_TIMEOUT*10))

echo "> Client $client_id status:"
$CHAIN_BINARY q ibc client status $client_id --home $whale_home
echo "> Client $client_id state:"
$CHAIN_BINARY q ibc client state $client_id -o json --home $whale_home | jq '.'
echo "> Client $client_id state frozen height:"
$CHAIN_BINARY q ibc client state $client_id -o json --home $whale_home | jq -r '.client_state.frozen_height'

echo "> Signing infos:"
infos=$($CHAIN_BINARY q slashing signing-infos --home $whale_home -o json)
echo "> Checking signing infos"
for (( i=0; i<$validator_count-1; i++ ))
do
  echo "> Home: ${homes[i]}"
  consensus_address=$($CHAIN_BINARY comet show-address --home ${homes[i]})
  tombstoned=$(echo $infos | jq -r --arg addr "$consensus_address" '.info[] | select(.address==$addr).tombstoned')
  if [[ "$tombstoned" == "true" ]]; then
      echo "> PASS: Validator has been tombstoned."
  else
      echo "> FAIL: Validator has not been tombstoned."
      exit 1
  fi
done
