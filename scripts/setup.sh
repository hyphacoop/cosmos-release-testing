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
jq -r --arg DENOM "$DENOM" '.app_state.crisis.constant_fee.denom = $DENOM' ${homes[0]}/config/genesis.json > temp/denom-1.json
jq -r --arg DENOM "$DENOM" '.app_state.mint.params.mint_denom = $DENOM' temp/denom-1.json > temp/denom-2.json
jq -r --arg DENOM "$DENOM" '.app_state.provider.params.consumer_reward_denom_registration_fee.denom = $DENOM' temp/denom-2.json > temp/denom-3.json
jq -r --arg DENOM "$DENOM" '.app_state.staking.params.bond_denom = $DENOM' temp/denom-3.json > temp/denom-4.json
jq -r --arg DENOM "$DENOM" '.app_state.gov.params.min_deposit[0].denom = $DENOM' temp/denom-4.json > temp/denom-5.json
jq -r --arg DENOM "$DENOM" '.app_state.gov.params.expedited_min_deposit[0].denom = $DENOM' temp/denom-5.json > temp/denom-6.json
cp temp/denom-6.json ${homes[0]}/config/genesis.json

echo "> Creating validators"
mkdir  -p ${homes[0]}/config//gentx
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
jq -r '.consensus_params.block.max_bytes = "2097152"' ${homes[0]}/config/genesis.json  > temp/blocksize.json
cp temp/blocksize.json ${homes[0]}/config/genesis.json

echo "> Patching genesis for slashing block window"
jq -r --arg WINDOW "$DOWNTIME_WINDOW" '.app_state.slashing.params.signed_blocks_window = $WINDOW' ${homes[0]}/config/genesis.json > temp/slashing.json
cp temp/slashing.json ${homes[0]}/config/genesis.json

echo "> Patching genesis for feemarket params"
jq -r '.app_state.feemarket.params.fee_denom |= "uatom"' ${homes[0]}/config/genesis.json > temp/feemarket-denom.json
mv temp/feemarket-denom.json ${homes[0]}/config/genesis.json
jq -r '.app_state.feemarket.params.min_base_gas_price |= "0.005"' ${homes[0]}/config/genesis.json > temp/feemarket-min-base.json
mv temp/feemarket-min-base.json ${homes[0]}/config/genesis.json
jq -r '.app_state.feemarket.state.base_gas_price |= "0.005"' ${homes[0]}/config/genesis.json > temp/feemarket-base.json
mv temp/feemarket-base.json ${homes[0]}/config/genesis.json


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
rm start.sh ; touch start.sh ; chmod +x start.sh ; echo "#!/bin/bash" >> start.sh
rm stop.sh ; touch stop.sh ; chmod +x stop.sh ; echo "#!/bin/bash" >> stop.sh
rm reset.sh ; touch reset.sh ; chmod +x reset.sh ; echo "#!/bin/bash" >> reset.sh

echo "echo \"Resetting chain...\"" >> reset.sh
echo "./stop.sh" >> reset.sh

echo "> Current folder:"
pwd
for i in $(seq 0 $[$validator_count-1])
do
    echo "echo \"Starting validator ${monikers[i]}...\"" >> start.sh
    if [ "$COSMOVISOR" = true ]; then
        echo "> Setting up with Cosmovisor"
        if [ "$UPGRADE_MECHANISM" = 'cv_auto' ]; then
            echo "tmux new-session -d -s ${monikers[i]} \"export DAEMON_NAME=$CHAIN_BINARY_NAME ; export DAEMON_HOME=${homes[i]} ; export DAEMON_LOG_BUFFER_SIZE=512 ; export DAEMON_ALLOW_DOWNLOAD_BINARIES=true ; cosmovisor run start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> start.sh
        else
            echo "tmux new-session -d -s ${monikers[i]} \"export DAEMON_NAME=$CHAIN_BINARY_NAME ; export DAEMON_HOME=${homes[i]} ; export DAEMON_LOG_BUFFER_SIZE=512 ; cosmovisor run start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> start.sh
        fi
    else
        echo "> Setting up without Cosmovisor"
        echo "tmux new-session -d -s ${monikers[i]} \"$CHAIN_BINARY start --home ${homes[i]} 2>&1 | tee ${logs[i]}\"" >> start.sh
    fi
    echo "sleep 0.2s" >> start.sh
    echo "echo \"Stopping validator ${monikers[i]}...\"" >> stop.sh
    echo "tmux send-keys -t ${monikers[i]} C-c" >> stop.sh
    echo "$CHAIN_BINARY tendermint unsafe-reset-all --home ${homes[i]}" >> reset.sh
    echo "sleep 0.2s" >> reset.sh
done

echo "./start.sh" >> reset.sh

echo "sleep 3s" >> start.sh
# echo "echo \"tmux sessions:\"" >> start.sh
# echo "tmux list-sessions" >> start.sh
echo "echo \"tmux sessions:\"" >> stop.sh
echo "tmux list-sessions" >> stop.sh

echo "> Setup complete."
echo "* Run start.sh to start the chain"
echo "* Run stop.sh to stop the chain"
echo "* Run reset.sh to reset the chain"