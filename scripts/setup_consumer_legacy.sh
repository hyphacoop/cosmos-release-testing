#!/bin/bash
# Initialize a consumer chain
# Legacy: pre-SDK v0.50

echo "Running with $CONSUMER_CHAIN_BINARY."

rm -rf contemp
mkdir contemp

PROVIDER_HOME=${home_prefix}001
echo "> Creating arrays"

monikers=()
homes=()
api_ports=()
rpc_ports=()
p2p_ports=()
grpc_ports=()
pprof_ports=()
logs=()
wallets=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$consumer_home_prefix$i
    homes+=($home)
    api_port=$consumer_api_prefix$i
    api_ports+=($api_port)
    rpc_port=$consumer_rpc_prefix$i
    rpc_ports+=($rpc_port)
    p2p_port=$consumer_p2p_prefix$i
    p2p_ports+=($p2p_port)
    grpc_port=$consumer_grpc_prefix$i
    grpc_ports+=($grpc_port)
    pprof_port=$consumer_pprof_prefix$i
    pprof_ports+=($pprof_port)
    log=$consumer_log_prefix$i
    logs+=($log)
done

echo "> Creating homes"
for i in $(seq 0 $[$validator_count-1])
do
    echo "> Home $i"
    $CONSUMER_CHAIN_BINARY config chain-id $CONSUMER_CHAIN_ID --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config keyring-backend test --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config broadcast-mode sync --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config node tcp://localhost:${rpc_ports[i]} --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY init ${monikers[i]} --chain-id $CHAIN_ID --home ${homes[i]} &> /dev/null
done
$CHAIN_BINARY q provider list-consumer-chains --home $PROVIDER_HOME -o json | jq -r '.chains[]'

# client_id=$($CHAIN_BINARY q provider list-consumer-chains --home $HOME_1 -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).client_id')
# echo "Client ID: $client_id"
# $CHAIN_BINARY q provider  consumer-id-from-client-id $client_id
# CONSUMER_ID=$($CHAIN_BINARY q provider  consumer-id-from-client-id $client_id)
echo "Consumer ID: $CONSUMER_ID"

echo "> Submitting opt-in txs"
for i in $(seq 0 $[validator_count-1])
do
    echo "> Opting in with ${monikers[i]}."
    pubkey=$($CHAIN_BINARY comet show-validator --home ${homes[i]})
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $pubkey --from ${monikers[i]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $PROVIDER_HOME -y -o json | jq -r '.txhash')
done

echo "> Updating genesis file with right denom."
# sed -i s%stake%$CONSUMER_DENOM%g $CONSUMER_HOME_1/config/genesis.json
jq --arg DENOM "$CONSUMER_DENOM" '.app_state.crisis.constant_fee.denom = $DENOM' ${homes[0]}/config/genesis.json > genesis-1.json
mv genesis-1.json ${homes[0]}/config/genesis.json

echo "> Setting for block max gas != -1."
jq -r '.consensus_params.block.max_gas = "50000000"' ${homes[0]}/config/genesis.json > consumer-gas.json
mv consumer-gas.json ${homes[0]}/config/genesis.json

echo "> Setting slashing to $CONSUMER_DOWNTIME_WINDOW"
jq -r --arg SLASH "$CONSUMER_DOWNTIME_WINDOW" '.app_state.slashing.params.signed_blocks_window |= $SLASH' ${homes[0]}/config/genesis.json > consumer-slashing.json
jq -r '.app_state.slashing.params.downtime_jail_duration |= "10s"' consumer-slashing.json > consumer-slashing-2.json
mv consumer-slashing-2.json ${homes[0]}/config/genesis.json

echo "> Creating and funding wallets."
echo "> Adding keys to first home"
echo $MNEMONIC_1 | $CONSUMER_CHAIN_BINARY keys add ${monikers[0]} --home ${homes[0]} --output json --recover > contemp/keys-${monikers[0]}.json
wallet=$(jq -r '.address' contemp/keys-${monikers[0]}.json)
wallets+=($wallet)
for i in $(seq 1 $[$validator_count-1])
do
    $CONSUMER_CHAIN_BINARY keys add ${monikers[i]} --home ${homes[0]} --output json > contemp/keys-${monikers[i]}.json
    wallet=$(jq -r '.address' temp/keys-${monikers[i]}.json)
    wallets+=($wallet)
    $CONSUMER_CHAIN_BINARY genesis add-genesis-account ${monikers[i]} $VAL_FUNDS$CONSUMER_DENOM --home ${homes[0]}
done

echo "> Copying genesis to all other homes"
for i in $(seq 1 $[$validator_count-1])
do
    cp ${homes[0]}/config/genesis.json ${homes[i]}/config/genesis.json
done

echo "> Configuring app.toml"
for i in $(seq 0 $[$validator_count-1])
do
    toml set --toml-path ${homes[i]}/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE"
    toml set --toml-path ${homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${homes[i]}/config/app.toml api.enabled-unsafe-cors true
    toml set --toml-path ${homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${api_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc.address "0.0.0.0:${grpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc-web.enable false
done

echo "> Configuring config.toml"
val1_node_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${homes[0]})
val1_peer="$val1_node_id@127.0.0.1:${p2p_ports[0]}"
for i in $(seq 0 $[$validator_count-1])
do
    toml set --toml-path ${homes[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${rpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${pprof_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${p2p_ports[i]}"
    sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' ${homes[i]}/config/config.toml
    sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${homes[i]}/config/config.toml
    toml set --toml-path ${homes[i]}/config/config.toml block_sync false
    toml set --toml-path ${homes[i]}/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers ""
    if [ $i -ne "0" ]; then
        toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers "$val1_peer"
    fi
done

echo "> Configuring session scripts"
rm start.sh ; touch start-$CONSUMER_CHAIN_ID.sh ; chmod +x start-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> start-$CONSUMER_CHAIN_ID.sh
rm stop.sh ; touch stop-$CONSUMER_CHAIN_ID.sh ; chmod +x stop-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> stop-$CONSUMER_CHAIN_ID.sh
rm reset.sh ; touch reset-$CONSUMER_CHAIN_ID.sh ; chmod +x reset-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> reset-$CONSUMER_CHAIN_ID.sh

echo "echo \"Resetting chain...\"" >> reset.sh
echo "./stop.sh" >> reset.sh

for i in $(seq 0 $[$validator_count-1])
do
    echo "echo \"Starting validator ${monikers[i]}...\"" >> start-$CONSUMER_CHAIN_ID.sh
    echo "tmux new-session -d -s ${monikers[i]} \"$CONSUMER_CHAIN_BINARY start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> start-$CONSUMER_CHAIN_ID.sh
    echo "sleep 0.2s" >> start.sh
    echo "echo \"Stopping validator ${monikers[i]}...\"" >> stop-$CONSUMER_CHAIN_ID.sh
    echo "tmux send-keys -t ${monikers[i]} C-c" >> stop-$CONSUMER_CHAIN_ID.sh
    echo "$CONSUMER_CHAIN_BINARY tendermint unsafe-reset-all --home ${homes[i]}" >> reset-$CONSUMER_CHAIN_ID.sh
    echo "sleep 0.2s" >> reset-$CONSUMER_CHAIN_ID.sh
done

echo "./start-$CONSUMER_CHAIN_ID.sh" >> reset-$CONSUMER_CHAIN_ID.sh

echo "sleep 3s" >> start-$CONSUMER_CHAIN_ID.sh
# echo "echo \"tmux sessions:\"" >> start.sh
# echo "tmux list-sessions" >> start.sh
echo "echo \"tmux sessions:\"" >> stop-$CONSUMER_CHAIN_ID.sh
echo "tmux list-sessions" >> stop-$CONSUMER_CHAIN_ID.sh
