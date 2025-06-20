#!/bin/bash
# Initialize a consumer chain

echo "Running with $CONSUMER_CHAIN_BINARY."

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
for i in $(seq -w 01 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    consumer_moniker=$consumer_moniker_prefix$i
    consumer_monikers+=($consumer_moniker)
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
    $CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config set client keyring-backend test --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config set client broadcast-mode sync --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY config set client node tcp://localhost:${rpc_ports[i]} --home ${homes[i]}
    $CONSUMER_CHAIN_BINARY init ${monikers[i]} --chain-id $CHAIN_ID --home ${homes[i]} &> /dev/null
done

$CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json --node http://localhost:$whale_rpc | jq -r '.chains[]'
echo "Consumer ID: $CONSUMER_ID"

echo "> Submitting opt-in txs"
for i in $(seq 0 $[validator_count-1])
do
    echo "> Opting in with ${monikers[i]}."
    pubkey=$($CHAIN_BINARY comet show-validator --home ${homes[i]})
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $pubkey --from ${monikers[i]} --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home $whale_home -y -o json | jq -r '.txhash')
done

echo "> Updating genesis file with right denom."
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
echo $MNEMONIC_RELAYER | $CONSUMER_CHAIN_BINARY keys add relayer --home ${homes[0]} --output json --recover > keys-relayer-$CONSUMER_CHAIN_ID.json
$CONSUMER_CHAIN_BINARY genesis add-genesis-account relayer $VAL_FUNDS$CONSUMER_DENOM --home ${homes[0]}

echo $MNEMONIC_1 | $CONSUMER_CHAIN_BINARY keys add ${consumer_monikers[0]} --home ${homes[0]} --output json --recover > keys-${consumer_monikers[0]}-$CONSUMER_CHAIN_ID.json
$CONSUMER_CHAIN_BINARY genesis add-genesis-account ${consumer_monikers[0]} $VAL_FUNDS$CONSUMER_DENOM --home ${homes[0]}
wallet=$(jq -r '.address' keys-${consumer_monikers[0]}-$CONSUMER_CHAIN_ID.json)
wallets+=($wallet)
for i in $(seq 1 $[$validator_count-1])
do
    $CONSUMER_CHAIN_BINARY keys add ${consumer_monikers[i]} --home ${homes[0]} --output json > keys-${consumer_monikers[i]}-$CONSUMER_CHAIN_ID.json
    wallet=$(jq -r '.address' keys-${consumer_monikers[i]}-$CONSUMER_CHAIN_ID.json)
    wallets+=($wallet)
    $CONSUMER_CHAIN_BINARY genesis add-genesis-account ${consumer_monikers[i]} $VAL_FUNDS$CONSUMER_DENOM --home ${homes[0]}
done

echo "> Consumer keys:"
$CONSUMER_CHAIN_BINARY keys list --home ${homes[0]}

# # Update genesis file with right denom
# if [ "$CONSUMER_CHAIN_BINARY" == "strided" ]; then
#     echo "Patching genesis file for Stride denom..."
#     jq '.app_state.crisis.constant_fee.denom = "ustrd"' $CONSUMER_HOME_1/config/genesis.json > stride-genesis-1.json
#     jq '.app_state.gov.params.min_deposit[0].denom = "ustrd"' stride-genesis-1.json > stride-genesis-2.json
#     jq '.app_state.mint.params.mint_denom = "ustrd"' stride-genesis-2.json > stride-genesis-3.json
#     jq '.app_state.staking.params.bond_denom = "ustrd"' stride-genesis-3.json > stride-genesis-4.json

#     echo "Patching genesis file for Stride fast governance..."
#     jq '(.app_state.epochs.epochs[] | select(.identifier=="day") ).duration = "120s"' stride-genesis-4.json  > stride-genesis-5.json
#     jq '(.app_state.epochs.epochs[] | select(.identifier=="stride_epoch") ).duration = "120s"' stride-genesis-5.json  > stride-genesis-6.json
#     jq '.app_state.gov.voting_params.voting_period = "30s"' stride-genesis-6.json  > stride-genesis-7.json
#     jq '.app_state.gov.params.voting_period = "30s"' stride-genesis-7.json  > stride-genesis-8.json

# elif [ "$CONSUMER_CHAIN_BINARY" == "neutrond" ]; then
#     jq --arg DENOM "$CONSUMER_DENOM" -r '.app_state.globalfee.params.minimum_gas_prices[0] |= {"amount": "0.02", "denom": $DENOM}' $CONSUMER_HOME_1/config/genesis.json > consumer-globalfee.json
#     mv consumer-globalfee.json $CONSUMER_HOME_1/config/genesis.json

#     echo "Patching genesis for feemarket params..."
#     jq -r '.app_state.feemarket.params.fee_denom |= "untrn"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-denom.json
#     mv feemarket-denom.json $CONSUMER_HOME_1/config/genesis.json
#     jq -r '.app_state.feemarket.params.min_base_gas_price |= "0.005"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-min-base.json
#     mv feemarket-min-base.json $CONSUMER_HOME_1/config/genesis.json
#     jq -r '.app_state.feemarket.state.base_gas_price |= "0.005"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-base.json
#     mv feemarket-base.json $HOMCONSUMER_HOME_1E_1/config/genesis.json
# fi

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
touch start-$CONSUMER_CHAIN_ID.sh ; chmod +x start-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> start-$CONSUMER_CHAIN_ID.sh
touch stop-$CONSUMER_CHAIN_ID.sh ; chmod +x stop-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> stop-$CONSUMER_CHAIN_ID.sh
touch reset-$CONSUMER_CHAIN_ID.sh ; chmod +x reset-$CONSUMER_CHAIN_ID.sh ; echo "#!/bin/bash" >> reset-$CONSUMER_CHAIN_ID.sh

echo "echo \"Resetting chain...\"" >> reset.sh
echo "./stop.sh" >> reset.sh

for i in $(seq 0 $[$validator_count-1])
do
    echo "echo \"Starting validator ${consumer_monikers[i]}...\"" >> start-$CONSUMER_CHAIN_ID.sh
    echo "tmux new-session -d -s ${consumer_monikers[i]} \"$CONSUMER_CHAIN_BINARY start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> start-$CONSUMER_CHAIN_ID.sh
    echo "sleep 0.2s" >> start-$CONSUMER_CHAIN_ID.sh
    echo "echo \"Stopping validator ${consumer_monikers[i]}...\"" >> stop-$CONSUMER_CHAIN_ID.sh
    echo "tmux send-keys -t ${consumer_monikers[i]} C-c" >> stop-$CONSUMER_CHAIN_ID.sh
    echo "$CONSUMER_CHAIN_BINARY tendermint unsafe-reset-all --home ${homes[i]}" >> reset-$CONSUMER_CHAIN_ID.sh
    echo "sleep 0.2s" >> reset-$CONSUMER_CHAIN_ID.sh
done

echo "./start-$CONSUMER_CHAIN_ID.sh" >> reset-$CONSUMER_CHAIN_ID.sh

echo "sleep 3s" >> start-$CONSUMER_CHAIN_ID.sh
# echo "echo \"tmux sessions:\"" >> start.sh
# echo "tmux list-sessions" >> start.sh
echo "echo \"tmux sessions:\"" >> stop-$CONSUMER_CHAIN_ID.sh
echo "tmux list-sessions" >> stop-$CONSUMER_CHAIN_ID.sh
