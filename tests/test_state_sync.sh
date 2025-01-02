#!/bin/bash
echo "> Creating arrays"

monikers=()
homes=()
api_ports=()
rpc_ports=()
p2p_ports=()
grpc_ports=()
pprof_ports=()
logs=()
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
    p2p_port=$p2p_prefix$i
    p2p_ports+=($p2p_port)
    grpc_port=$grpc_prefix$i
    grpc_ports+=($grpc_port)
    pprof_port=$pprof_prefix$i
    pprof_ports+=($pprof_port)
    log=$log_prefix$i
    logs+=($log)
done

home=.statesync
rpc_port=${rpc_prefix}999
api_port=${api_prefix}999
p2p_port=${p2p_prefix}999
grpc_port=${grpc_prefix}999
pprof_port=${pprof_prefix}999
log=${log_prefix}999
echo "> Creating home"
$CHAIN_BINARY config set client chain-id $CHAIN_ID --home $home
$CHAIN_BINARY config set client keyring-backend test --home $home
$CHAIN_BINARY config set client broadcast-mode sync --home $home
$CHAIN_BINARY config set client node tcp://localhost:$rpc_port --home $home
$CHAIN_BINARY init statesync --chain-id $CHAIN_ID --home $home &> /dev/null

echo "> Copying genesis"
cp ${homes[0]}/config/genesis.json $home/config/genesis.json

echo "> Peer app.toml:"
cat ${homes[0]}/config/app.toml
echo "> Peer config.toml:"
cat ${homes[0]}/config/config.toml

echo "> Wait for state sync snapshot"
sleep $[ $TIMEOUT_COMMIT*$STATE_SYNC_INTERVAL ]

echo "> Collect block height and hash"
status=$($CHAIN_BINARY status --home ${homes[0]})
height=$(echo $status | jq -r '.sync_info.latest_block_height')
hash=$(echo $status | jq -r '.sync_info.latest_block_hash')
echo "Height: $height, hash: $hash"

toml set --toml-path $home/config/app.toml minimum-gas-prices "$GAS_PRICE"
toml set --toml-path $home/config/app.toml api.enable true
toml set --toml-path $home/config/app.toml api.enabled-unsafe-cors true
toml set --toml-path $home/config/app.toml api.address "tcp://0.0.0.0:$api_port"
toml set --toml-path $home/config/app.toml grpc.address "0.0.0.0:$grpc_port"
toml set --toml-path $home/config/app.toml grpc-web.enable false

echo "> Configuring config.toml"
val1_node_id=$($CHAIN_BINARY tendermint show-node-id --home ${homes[0]})
state_sync_node_id=$($CHAIN_BINARY tendermint show-node-id --home ${homes[-1]})
val1_peer="$val1_node_id@127.0.0.1:${p2p_ports[0]}"
state_sync_peer="$state_sync_node_id@127.0.0.1:${p2p_ports[-1]}"
toml set --toml-path $home/config/config.toml rpc.laddr "tcp://0.0.0.0:$rpc_port"
toml set --toml-path $home/config/config.toml rpc.pprof_laddr "0.0.0.0:$pprof_port"
toml set --toml-path $home/config/config.toml p2p.laddr "tcp://0.0.0.0:$p2p_port"
# toml set --toml-path $home/config/config.toml p2p.addr_book_strict false
sed -i -e '/addr_book_strict =/ s/= .*/= false/' $home/config/config.toml
# toml set --toml-path $home/config/config.toml p2p.allow_duplicate_ip true
sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' $home/config/config.toml
toml set --toml-path $home/config/config.toml block_sync false
toml set --toml-path $home/config/config.toml consensus.timeout_commit "${TIMEOUT_COMMIT}s"
# toml set --toml-path $home/config/config.toml p2p.persistent_peers "$val1_peer,$state_sync_peer"
# toml set --toml-path $home/config/config.toml p2p.persistent_peers "$val1_peer"
# sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${homes[i]}/config/config.toml
toml set --toml-path $home/config/config.toml statesync.enable true
toml set --toml-path $home/config/config.toml statesync.rpc_servers "http://127.0.0.1:${rpc_ports[-1]},http://127.0.0.1:${rpc_ports[-1]}"
toml set --toml-path $home/config/config.toml statesync.trust_height $height
toml set --toml-path $home/config/config.toml statesync.trust_hash $hash
# cat $home/config/config.toml

echo "> Copying address book from validator 1:"
cp ${homes[0]}/config/addrbook.json $home/config/addrbook.json
cat $home/config/addrbook.json

echo "> Starting state sync node"
tmux new-session -d -s statesync "$CHAIN_BINARY start --home $home 2>&1 | tee $log"

sleep 120
catchingup=$(curl -s http://localhost:$rpc_port/status | jq -r .result.sync_info.catching_up)
echo "> Catching up: $catchingup"
tail -n 10 $log
tail -n 10 ${logs[-1]}

exit 0
# until [ "$catchingup" = "false" ]
# do
#     sleep $TIMEOUT_COMMIT
#     catchingup=$(curl -s http://localhost:$rpc_port/status | jq -r .result.sync_info.catching_up)
#     echo "> Catching up: $catchingup"
#     echo "> Test node log:"
#     tail -n 10 $log
#     # echo "> State sync node log:"
#     # tail -n 10 ${logs[-1]}
# done

