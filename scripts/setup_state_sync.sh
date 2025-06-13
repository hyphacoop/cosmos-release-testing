#!/bin/bash

rm -rf $node_home

echo "> Syncing new node"

echo "> Creating home"
$CHAIN_BINARY config set client chain-id $CHAIN_ID --home $node_home
$CHAIN_BINARY config set client keyring-backend test --home $node_home
$CHAIN_BINARY config set client broadcast-mode sync --home $node_home
$CHAIN_BINARY config set client node tcp://localhost:${rpc_prefix}999 --home $node_home
$CHAIN_BINARY init statesync --chain-id $CHAIN_ID --home $node_home &> /dev/null

echo "> Copying genesis file"
cp $whale_home/config/genesis.json $node_home/config/genesis.json

echo "> Configuring app.toml"
toml set --toml-path $node_home/config/app.toml minimum-gas-prices "$GAS_PRICE"
toml set --toml-path $node_home/config/app.toml api.enable true
toml set --toml-path $node_home/config/app.toml api.enabled-unsafe-cors true
toml set --toml-path $node_home/config/app.toml api.address "tcp://0.0.0.0:${api_prefix}999"
toml set --toml-path $node_home/config/app.toml grpc.address "0.0.0.0:${grpc_prefix}999"
toml set --toml-path $node_home/config/app.toml grpc-web.enable false
toml set --toml-path $node_home/config/app.toml state-sync.snapshot-interval 50
toml set --toml-path $node_home/config/app.toml state-sync.snapshot-keep-recent 5

echo "> Configuring config.toml"
val1_node_id=$($CHAIN_BINARY comet show-node-id --home ${whale_home})
val1_peer="$val1_node_id@localhost:${p2p_prefix}001"
toml set --toml-path $node_home/config/config.toml rpc.laddr "tcp://0.0.0.0:${rpc_prefix}999"
toml set --toml-path $node_home/config/config.toml rpc.pprof_laddr "localhost:${pprof_prefix}999"
toml set --toml-path $node_home/config/config.toml p2p.laddr "tcp://0.0.0.0:${p2p_prefix}999"
toml set --toml-path $node_home/config/config.toml p2p.allow_duplicate_ip true
toml set --toml-path $node_home/config/config.toml block_sync false
toml set --toml-path $node_home/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
toml set --toml-path $node_home/config/config.toml p2p.persistent_peers "$val1_peer"

echo "> Configuring state-sync"
CURRENT_BLOCK=$(curl -s http://localhost:${rpc_prefix}001/block | jq -r '.result.block.header.height')
echo "> Current block: $CURRENT_BLOCK"
TRUST_HEIGHT=$[ $CURRENT_BLOCK-50 ]
echo "> Trust height: $TRUST_HEIGHT"
TRUST_BLOCK=$(curl -s http://localhost:${rpc_prefix}001/block\?height\=$TRUST_HEIGHT)
TRUST_HASH=$(echo $TRUST_BLOCK | jq -r '.result.block_id.hash')
echo "> Trust hash: $TRUST_HASH"
toml set --toml-path $node_home/config/config.toml statesync.enable true
toml set --toml-path $node_home/config/config.toml statesync.rpc_servers "http://localhost:${rpc_prefix}003,http://localhost:${rpc_prefix}003"
toml set --toml-path $node_home/config/config.toml statesync.trust_height $TRUST_HEIGHT
toml set --toml-path $node_home/config/config.toml statesync.trust_hash $TRUST_HASH

echo "> Configuring session scripts"
rm $START_SCRIPT ; touch $START_SCRIPT ; chmod +x $START_SCRIPT ; echo "#!/bin/bash" >> $START_SCRIPT
rm $STOP_SCRIPT ; touch $STOP_SCRIPT ; chmod +x $STOP_SCRIPT ; echo "#!/bin/bash" >> $STOP_SCRIPT
rm $RESET_SCRIPT ; touch $RESET_SCRIPT ; chmod +x $RESET_SCRIPT ; echo "#!/bin/bash" >> $RESET_SCRIPT


echo "echo \"Starting state sync node... \"" >> $START_SCRIPT
echo "tmux new-session -d -s statesync \"$CHAIN_BINARY start --home $node_home 2>&1 | tee ${logs[i]}\"" >> $START_SCRIPT
echo "sleep 0.2s" >> $START_SCRIPT
echo "sleep 3s" >> $START_SCRIPT
echo "echo \"tmux sessions:\"" >> $STOP_SCRIPT
echo "tmux list-sessions" >> $STOP_SCRIPT

echo "echo \"Stopping statesync node...\"" >> $STOP_SCRIPT
echo "tmux send-keys -t statesync C-c" >> $STOP_SCRIPT
echo "echo \"tmux sessions:\"" >> $STOP_SCRIPT
echo "tmux list-sessions" >> $STOP_SCRIPT

echo "echo \"Resetting statesync node...\"" >> $RESET_SCRIPT
echo "./$STOP_SCRIPT" >> $RESET_SCRIPT
echo "$CHAIN_BINARY tendermint unsafe-reset-all --home $node_home" >> $RESET_SCRIPT
echo "sleep 0.2s" >> $RESET_SCRIPT
echo "./$START_SCRIPT" >> $RESET_SCRIPT

echo "> Setup complete."
echo "* Run $START_SCRIPT to start the chain"
echo "* Run $STOP_SCRIPT to stop the chain"
echo "* Run $RESET_SCRIPT to reset the chain"