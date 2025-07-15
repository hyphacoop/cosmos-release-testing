#!/bin/bash
# Configure variables before running this file.
# source vars.sh

echo "> Downloading binary..."
wget $CHAIN_BINARY_URL -q -O $CHAIN_BINARY
chmod +x $CHAIN_BINARY
$CHAIN_BINARY version

rm -rf temp
mkdir temp

echo "> Creating a $validator_count-validator chain"
# We are only after a single thing: Create an N-validator chain without creating multiple services
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
operators=()
for i in $(seq -w 01 $validator_count)
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

echo "> Creating homes"
for i in $(seq 0 $[$validator_count-1])
do
    echo "> Home $i"
    $CHAIN_BINARY config set client chain-id $CHAIN_ID --home ${homes[i]}
    $CHAIN_BINARY config set client keyring-backend test --home ${homes[i]}
    $CHAIN_BINARY config set client broadcast-mode sync --home ${homes[i]}
    $CHAIN_BINARY config set client node tcp://localhost:${rpc_ports[i]} --home ${homes[i]}
    $CHAIN_BINARY init ${monikers[i]} --chain-id $CHAIN_ID --home ${homes[i]} &> /dev/null

    if [ "$COSMOVISOR" = true ]; then
        mkdir -p ${homes[i]}/cosmovisor/genesis/bin
        cp $CHAIN_BINARY ${homes[i]}/cosmovisor/genesis/bin/
    fi
done

echo "> Adding keys to first home"
echo $MNEMONIC_RELAYER | $CHAIN_BINARY keys add relayer --home ${homes[0]} --output json --recover > temp/keys-relayer.json
echo $MNEMONIC_1 | $CHAIN_BINARY keys add ${monikers[0]} --home ${homes[0]} --output json --recover > temp/keys-${monikers[0]}.json
wallet=$(jq -r '.address' temp/keys-${monikers[0]}.json)
operator=$($CHAIN_BINARY debug bech32-convert --prefix cosmosvaloper $wallet)
wallets+=($wallet)
operators+=($operator)
for i in $(seq 1 $[$validator_count-1])
do
    $CHAIN_BINARY keys add ${monikers[i]} --home ${homes[0]} --output json > temp/keys-${monikers[i]}.json
    wallet=$(jq -r '.address' temp/keys-${monikers[i]}.json)
    operator=$($CHAIN_BINARY debug bech32-convert --prefix cosmosvaloper $wallet)
    wallets+=($wallet)
    operators+=($operator)
done

echo "> Updating genesis file with specified denom"
echo "> Updating crisis denom"
jq -r --arg DENOM "$DENOM" '.app_state.crisis.constant_fee.denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-crisis.json
cp temp/denom-crisis.json ${homes[0]}/config/genesis.json

echo "> Updating mint denom"
jq -r --arg DENOM "$DENOM" '.app_state.mint.params.mint_denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-mint.json
cp temp/denom-mint.json ${homes[0]}/config/genesis.json

echo "> Updating provider denom"
jq -r --arg DENOM "$DENOM" '.app_state.provider.params.consumer_reward_denom_registration_fee.denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-provider.json
cp temp/denom-provider.json ${homes[0]}/config/genesis.json

echo "> Updating staking denom"
jq -r --arg DENOM "$DENOM" '.app_state.staking.params.bond_denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-staking.json
cp temp/denom-staking.json ${homes[0]}/config/genesis.json

echo "> Updating gov denom"
jq -r --arg DENOM "$DENOM" '.app_state.gov.params.min_deposit[0].denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-dep.json
cp temp/denom-dep.json ${homes[0]}/config/genesis.json

echo "> Updating gov expedited denom"
jq -r --arg DENOM "$DENOM" '.app_state.gov.params.expedited_min_deposit[0].denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-exp.json
cp temp/denom-exp.json ${homes[0]}/config/genesis.json

echo "> Creating validators"
mkdir  -p ${homes[0]}/config/gentx
$CHAIN_BINARY genesis add-genesis-account relayer $VAL_FUNDS$DENOM --home ${homes[0]}

for i in $(seq 0 $[$validator_count-1])
do
    $CHAIN_BINARY genesis add-genesis-account ${monikers[i]} $VAL_FUNDS$DENOM --home ${homes[0]}
    node_id=$($CHAIN_BINARY tendermint show-node-id --home ${homes[i]})
    increase=$(echo "$VAL_STAKE * ($validator_count - $i)" | bc)
    stake=$[ $VAL_STAKE + $increase ]
    if [ $i -eq "0" ]; then
        stake=$VAL_WHALE
    fi
    echo "Stake: $stake"
    $CHAIN_BINARY genesis gentx \
        ${monikers[i]} $stake$DENOM \
        --pubkey "$($CHAIN_BINARY tendermint show-validator --home ${homes[i]})" \
        --node-id $node_id \
        --moniker ${monikers[i]} \
        --chain-id $CHAIN_ID \
        --home ${homes[0]} \
        --output-document ${homes[0]}/config/gentx/${monikers[i]}-gentx.json  &> /dev/null
done
$CHAIN_BINARY genesis collect-gentxs --home ${homes[0]}  &> /dev/null

echo "> Patching genesis file for 1 block epochs"
jq -r '.app_state.provider.params.blocks_per_epoch = 1' ${homes[0]}/config/genesis.json  > temp/bpe.json
cp temp/bpe.json ${homes[0]}/config/genesis.json

echo "> Patching genesis file for max consensus validators"
jq -r '.app_state.provider.params.max_provider_consensus_validators = 50' ${homes[0]}/config/genesis.json  > temp/bpe.json
cp temp/bpe.json ${homes[0]}/config/genesis.json

echo "> Patching genesis file for max validators"
jq -r '.app_state.staking.params.max_validators = 100' ${homes[0]}/config/genesis.json  > temp/vals.json
cp temp/vals.json ${homes[0]}/config/genesis.json

echo "> Patching genesis file for deposit period"
jq -r --arg DEPOSIT "${DEPOSIT_PERIOD}s" '.app_state.gov.params.max_deposit_period = $DEPOSIT' ${homes[0]}/config/genesis.json  > temp/deposit.json
cp temp/deposit.json ${homes[0]}/config/genesis.json

echo "> Patching genesis file for expedited voting period"
jq -r --arg VOTING "${EXPEDITED_VOTING_PERIOD}s" '.app_state.gov.params.expedited_voting_period = $VOTING' ${homes[0]}/config/genesis.json  > temp/voting.json
cp temp/voting.json ${homes[0]}/config/genesis.json

echo "> Patching genesis file for voting period"
jq -r --arg VOTING "${VOTING_PERIOD}s" '.app_state.gov.params.voting_period = $VOTING' ${homes[0]}/config/genesis.json  > temp/voting.json
cp temp/voting.json ${homes[0]}/config/genesis.json


echo "> Patching genesis for 2MiB block size"
jq -r '.consensus.params.block.max_bytes = "20000000"' ${homes[0]}/config/genesis.json  > temp/blocksize.json
cp temp/blocksize.json ${homes[0]}/config/genesis.json
echo "> Patching genesis for 50M gas limit"
jq -r '.consensus.params.block.max_gas = "50000000"' ${homes[0]}/config/genesis.json  > temp/blockgas.json
cp temp/blockgas.json ${homes[0]}/config/genesis.json

echo "> Patching genesis for slashing block window"
jq -r --arg WINDOW "$DOWNTIME_WINDOW" '.app_state.slashing.params.signed_blocks_window = $WINDOW' ${homes[0]}/config/genesis.json > temp/slashing.json
cp temp/slashing.json ${homes[0]}/config/genesis.json

echo "> Patching genesis for feemarket params"
jq -r '.app_state.feemarket.params.fee_denom |= "uatom"' ${homes[0]}/config/genesis.json > temp/feemarket-denom.json
mv temp/feemarket-denom.json ${homes[0]}/config/genesis.json
jq -r '.app_state.feemarket.params.max_block_utilization |= "50000000"' ${homes[0]}/config/genesis.json > temp/feemarket-gas.json
mv temp/feemarket-gas.json ${homes[0]}/config/genesis.json
jq -r '.app_state.feemarket.params.min_base_gas_price |= "0.005"' ${homes[0]}/config/genesis.json > temp/feemarket-min-base.json
mv temp/feemarket-min-base.json ${homes[0]}/config/genesis.json
jq -r '.app_state.feemarket.state.base_gas_price |= "0.005"' ${homes[0]}/config/genesis.json > temp/feemarket-base.json
mv temp/feemarket-base.json ${homes[0]}/config/genesis.json

jq '.' ${homes[0]}/config/genesis.json

echo "> Copying genesis to all other homes"
for i in $(seq 1 $[$validator_count-1])
do
    cp ${homes[0]}/config/genesis.json ${homes[i]}/config/genesis.json
done

echo "> Configuring app.toml"
for i in $(seq 0 $[$validator_count-1])
do
    toml set --toml-path ${homes[i]}/config/app.toml minimum-gas-prices "$GAS_PRICE"
    toml set --toml-path ${homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${homes[i]}/config/app.toml api.enabled-unsafe-cors true
    toml set --toml-path ${homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${api_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc.address "0.0.0.0:${grpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc-web.enable false
    toml set --toml-path ${homes[i]}/config/app.toml state-sync.snapshot-interval $STATE_SYNC_SNAPSHOT_INTERVAL
    toml set --toml-path ${homes[i]}/config/app.toml state-sync.snapshot-keep-recent $STATE_SYNC_SNAPSHOT_KEEP_RECENT
done

echo "> Configuring config.toml"
val1_node_id=$($CHAIN_BINARY tendermint show-node-id --home ${homes[0]})
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
rm $START_SCRIPT ; touch $START_SCRIPT ; chmod +x $START_SCRIPT ; echo "#!/bin/bash" >> $START_SCRIPT
rm $STOP_SCRIPT ; touch $STOP_SCRIPT ; chmod +x $STOP_SCRIPT ; echo "#!/bin/bash" >> $STOP_SCRIPT
rm $RESET_SCRIPT ; touch $RESET_SCRIPT ; chmod +x $RESET_SCRIPT ; echo "#!/bin/bash" >> $RESET_SCRIPT

echo "echo \"Resetting chain...\"" >> $RESET_SCRIPT
echo "./$STOP_SCRIPT" >> $RESET_SCRIPT

echo "> Current folder:"
pwd
for i in $(seq 0 $[$validator_count-1])
do
    echo "echo \"Starting validator ${monikers[i]}...\"" >> $START_SCRIPT
    if [ "$COSMOVISOR" = true ]; then
        echo "> Setting up with Cosmovisor"
        if [ "$UPGRADE_MECHANISM" = 'cv_auto' ]; then
            echo "tmux new-session -d -s ${monikers[i]} \"export DAEMON_NAME=$CHAIN_BINARY_NAME ; export DAEMON_HOME=${homes[i]} ; export DAEMON_LOG_BUFFER_SIZE=512 ; export DAEMON_ALLOW_DOWNLOAD_BINARIES=true ; cosmovisor run start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> $START_SCRIPT
        else
            echo "tmux new-session -d -s ${monikers[i]} \"export DAEMON_NAME=$CHAIN_BINARY_NAME ; export DAEMON_HOME=${homes[i]} ; export DAEMON_LOG_BUFFER_SIZE=512 ; cosmovisor run start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> $START_SCRIPT
        fi
    else
        echo "> Setting up without Cosmovisor"
        echo "tmux new-session -d -s ${monikers[i]} \"$CHAIN_BINARY start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> $START_SCRIPT
    fi
    echo "sleep 0.2s" >> $START_SCRIPT
    echo "echo \"Stopping validator ${monikers[i]}...\"" >> $STOP_SCRIPT
    echo "tmux send-keys -t ${monikers[i]} C-c" >> $STOP_SCRIPT
    echo "$CHAIN_BINARY tendermint unsafe-reset-all --home ${homes[i]}" >> $RESET_SCRIPT
    echo "sleep 0.2s" >> $RESET_SCRIPT
done

echo "./$START_SCRIPT" >> $RESET_SCRIPT

echo "sleep 3s" >> $START_SCRIPT
# echo "echo \"tmux sessions:\"" >> $START_SCRIPT
# echo "tmux list-sessions" >> $START_SCRIPT
echo "echo \"tmux sessions:\"" >> $STOP_SCRIPT
echo "tmux list-sessions" >> $STOP_SCRIPT

echo "> Setup complete."
echo "* Run $START_SCRIPT to start the chain"
echo "* Run $STOP_SCRIPT to stop the chain"
echo "* Run $RESET_SCRIPT to reset the chain"