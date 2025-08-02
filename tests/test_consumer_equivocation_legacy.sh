#!/bin/bash

expanded_count=$(( $validator_count+1 ))

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
for i in $(seq -w 01 $expanded_count)
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

echo "> Configuring provider node"
peer_id=$($CHAIN_BINARY comet show-node-id --home ${homes[1]})
peer="$peer_id@127.0.0.1:${p2p_ports[1]}"

for (( i=$validator_count; i<$expanded_count; i++ ))
do
    echo "> Home $i"
    $CHAIN_BINARY config set client chain-id $CHAIN_ID --home ${homes[i]}
    $CHAIN_BINARY config set client keyring-backend test --home ${homes[i]}
    $CHAIN_BINARY config set client broadcast-mode sync --home ${homes[i]}
    $CHAIN_BINARY config set client node tcp://localhost:${rpc_ports[i]} --home ${homes[i]}
    $CHAIN_BINARY init ${monikers[i]} --chain-id $CHAIN_ID --home ${homes[i]} &> /dev/null

    toml set --toml-path ${homes[i]}/config/app.toml minimum-gas-prices "$GAS_PRICE"
    toml set --toml-path ${homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${homes[i]}/config/app.toml api.enabled-unsafe-cors true
    toml set --toml-path ${homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${api_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc.address "0.0.0.0:${grpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc-web.enable false

    toml set --toml-path ${homes[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${rpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${pprof_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${p2p_ports[i]}"
    sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' ${homes[i]}/config/config.toml
    sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${homes[i]}/config/config.toml
    toml set --toml-path ${homes[i]}/config/config.toml block_sync false
    toml set --toml-path ${homes[i]}/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers ""
    
    echo "> Set peer"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers "$peer"
done

echo "> Copy snapshot from whale"
session=${monikers[0]}
echo "> Session: $session"
tmux send-keys -t $session C-c
cp ${homes[-1]}/data/priv_validator_state.json ./state.bak

cp -r ${homes[0]}/data ${homes[-1]}/
cp ./state.bak ${homes[-1]}/data/priv_validator_state.json
cp ${homes[0]}/config/genesis.json ${homes[-1]}/config/genesis.json
tmux new-session -d -s $session "$CHAIN_BINARY start --home ${homes[0]} 2>&1 | tee ${logs[0]}"
tmux new-session -d -s ${monikers[-1]} "$CHAIN_BINARY start --home ${homes[-1]} 2>&1 | tee ${logs[-1]}"
sleep 20

eqwallet=$($CHAIN_BINARY keys add eqval --home ${homes[-1]} --output json | jq -r '.address')
echo "> New wallet: $eqwallet"
echo "> Fund new validator"
$CHAIN_BINARY tx bank send $WALLET_1 $eqwallet $VAL_WHALE$DENOM --home $whale_home --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json | jq '.'
sleep $(($COMMIT_TIMEOUT*2))
pubkey=$($CHAIN_BINARY comet show-validator --home ${homes[-1]})
amount=$VAL_STAKE$DENOM

jq --argjson pubkey "$pubkey" '.pubkey |= $pubkey' templates/create-validator.json > eqval.json
jq '.moniker |= "eqval"' eqval.json > eqval-moniker.json
cp eqval-moniker.json eqval.json
jq '.moniker |= "eqval"' eqval.json > eqval-moniker.json
cp eqval-moniker.json eqval.json
jq --arg amount "$amount" '.amount |= $amount' eqval.json > eqval-stake.json
cp eqval-stake.json eqval.json

jq '.' eqval.json
echo "> Create validator"
$CHAIN_BINARY tx staking create-validator eqval.json --from $eqwallet --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[-1]} -y
sleep $(($COMMIT_TIMEOUT*2))
status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r '.validators[] | select(.description.moniker == "eqval").status')
if [ $status == "BOND_STATUS_BONDED" ]; then
  echo "> Validator was created successfully."
else
  echo "> Validator was not created successfully."
  exit 1
fi

# Consumer nodes
expanded_count=$(( $validator_count+2 ))

consumer_monikers=()
consumer_homes=()
consumer_api_ports=()
consumer_rpc_ports=()
consumer_p2p_ports=()
consumer_grpc_ports=()
consumer_pprof_ports=()
consumer_logs=()
for i in $(seq -w 01 $expanded_count)
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
done

echo "> Configuring consumer nodes"
peer_a_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes[1]})
peer_a="$peer_a_id@127.0.0.1:${consumer_p2p_ports[1]}"
peer_b_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes[2]})
peer_b="$peer_b_id@127.0.0.1:${consumer_p2p_ports[2]}"


for (( i=$validator_count; i<$expanded_count; i++ ))
do
    echo "> Home $i"
    $CONSUMER_CHAIN_BINARY config chain-id $CONSUMER_CHAIN_ID --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config keyring-backend test --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config broadcast-mode sync --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config node tcp://localhost:${consumer_rpc_ports[i]} --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY init ${consumer_monikers[i]} --chain-id $CONSUMER_CHAIN_ID --home ${consumer_homes[i]} &> /dev/null

    toml set --toml-path ${consumer_homes[i]}/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.enabled-unsafe-cors true
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${consumer_api_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml grpc.address "0.0.0.0:${consumer_grpc_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml grpc-web.enable false

    toml set --toml-path ${consumer_homes[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${consumer_rpc_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${consumer_pprof_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${consumer_p2p_ports[i]}"
    sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' ${consumer_homes[i]}/config/config.toml
    sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${consumer_homes[i]}/config/config.toml
    toml set --toml-path ${consumer_homes[i]}/config/config.toml block_sync false
    toml set --toml-path ${consumer_homes[i]}/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers ""
    if [ $i == $validator_count ]; then
        echo "> Set peer A"
        toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers "$peer_a"
    else
        echo "> Set peer B"
        toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers "$peer_b"
    fi
done

echo "> Opt in with new validator."
consumer_pubkey=$($CONSUMER_CHAIN_BINARY tendermint show-validator --home ${consumer_homes[-2]})
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chainid "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chainid).consumer_id')
echo "> Consumer id: $consumer_id, pubkey: $consumer_pubkey"
$CHAIN_BINARY tx provider opt-in $consumer_id $consumer_pubkey --from $eqwallet --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[-1]} -y
sleep $(($COMMIT_TIMEOUT*2))

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


tmux new-session -d -s $session "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[0]} 2>&1 | tee ${consumer_logs[0]}"
tmux new-session -d -s ${consumer_monikers[-2]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-2]} 2>&1 | tee ${consumer_logs[-2]}"
tmux new-session -d -s ${consumer_monikers[-1]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-1]} 2>&1 | tee ${consumer_logs[-1]}"
sleep 60
echo "> Whale node:"
tail ${consumer_logs[0]} -n 100
echo "> Node A (${consumer_monikers[-2]}):"
tail ${consumer_logs[-2]} -n 100
echo "> Node B (${consumer_monikers[-1]}):"
tail ${consumer_logs[-1]} -n 100

echo "> Consumer:"
$CONSUMER_CHAIN_BINARY q slashing signing-infos --home ${consumer_whale_home}
echo "> Provider:"
$CHAIN_BINARY q slashing signing-infos --home ${whale_home}

exit 0

# Test equivocation proposal for double-signing
EQ_PROVIDER_HOME=/home/runner/.eqp
EQ_PROVIDER_SERVICE=eq_provider.service
EQ_PROV_API_PORT=20002
EQ_PROV_GRPC_PORT=2012
EQ_PROV_RPC_PORT=2022
EQ_PROV_P2P_PORT=2032
EQ_PROV_PPROF_PORT=2042
EQ_CONSUMER_HOME_1=/home/runner/.eqc1
EQ_CONSUMER_HOME_2=/home/runner/.eqc2
EQ_CONSUMER_SERVICE_1=eq_consumer_1.service
EQ_CONSUMER_SERVICE_2=eq_consumer_2.service
EQ_CON_API_PORT_1=2102
EQ_CON_API_PORT_2=2202
EQ_CON_GRPC_PORT_1=2112
EQ_CON_GRPC_PORT_2=2212
EQ_CON_RPC_PORT_1=2122
EQ_CON_RPC_PORT_2=2222
EQ_CON_P2P_PORT_1=2132
EQ_CON_P2P_PORT_2=2232
EQ_CON_PPROF_PORT_1=2142
EQ_CON_PPROF_PORT_2=2242

FUND_AMOUNT=1000000000
STAKE_AMOUNT=8000000
UNBOND_AMOUNT=2000000
REDELEGATE_AMOUNT=1000000
SLASH_FACTOR=0.05

# source tests/process_tx.sh

echo "Setting up provider node..."
$CHAIN_BINARY config set client chain-id $CHAIN_ID --home $EQ_PROVIDER_HOME
$CHAIN_BINARY config set client keyring-backend test --home $EQ_PROVIDER_HOME
$CHAIN_BINARY config set client  node tcp://localhost:$EQ_PROV_RPC_PORT --home $EQ_PROVIDER_HOME
$CHAIN_BINARY init malval_det --chain-id $CHAIN_ID --home $EQ_PROVIDER_HOME
cp $EQ_PROVIDER_HOME/config/priv_validator_key.json ./
cp $EQ_PROVIDER_HOME/config/node_key.json ./

echo "Copying snapshot from validator 2..."
sudo systemctl stop $PROVIDER_SERVICE_2
cp -R $HOME_2/data/application.db $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/blockstore.db $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/cs.wal $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/evidence.db $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/snapshots $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/state.db $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/tx_index.db $EQ_PROVIDER_HOME/data/
cp -R $HOME_2/data/upgrade-info.json $EQ_PROVIDER_HOME/data/
sudo systemctl start $PROVIDER_SERVICE_2
# sleep 10

echo "Getting genesis file..."
cp $HOME_1/config/genesis.json $EQ_PROVIDER_HOME/config/genesis.json
cp $HOME_1/config/app.toml $EQ_PROVIDER_HOME/config/app.toml
cp $HOME_1/config/config.toml $EQ_PROVIDER_HOME/config/config.toml

echo "Patching config files..."
# app.toml
# minimum_gas_prices
# sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$DENOM\"^" $EQ_PROVIDER_HOME/config/app.toml
# Enable API
# toml set --toml-path $EQ_PROVIDER_HOME/config/app.toml api.enable true
# Set different ports for api
toml set --toml-path $EQ_PROVIDER_HOME/config/app.toml api.address "tcp://0.0.0.0:$EQ_PROV_API_PORT"
# Set different ports for grpc
toml set --toml-path $EQ_PROVIDER_HOME/config/app.toml grpc.address "0.0.0.0:$EQ_PROV_GRPC_PORT"
# Turn off grpc web
# toml set --toml-path $EQ_PROVIDER_HOME/config/app.toml grpc-web.enable false
# config.toml
# Set different ports for rpc
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml rpc.laddr "tcp://0.0.0.0:$EQ_PROV_RPC_PORT"
# Set different ports for rpc pprof
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml rpc.pprof_laddr "localhost:$EQ_PROV_PPROF_PORT"
# Set different ports for p2p
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml p2p.laddr "tcp://0.0.0.0:$EQ_PROV_P2P_PORT"
# Allow duplicate IPs in p2p
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml p2p.allow_duplicate_ip true
echo "Setting a short commit timeout..."
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
# Set persistent peers
echo "Setting persistent peers..."
VAL2_NODE_ID=$($CHAIN_BINARY tendermint show-node-id --home $HOME_2)
VAL3_NODE_ID=$($CHAIN_BINARY tendermint show-node-id --home $HOME_3)
VAL2_PEER="$VAL2_NODE_ID@localhost:$VAL2_P2P_PORT"
VAL3_PEER="$VAL3_NODE_ID@localhost:$VAL3_P2P_PORT"
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml p2p.persistent_peers "$VAL2_PEER,$VAL3_PEER"
# Set fast_sync to false
toml set --toml-path $EQ_PROVIDER_HOME/config/config.toml fast_sync false

echo "Create new validator key..."
$CHAIN_BINARY keys add malval_det --home $EQ_PROVIDER_HOME
malval_det=$($CHAIN_BINARY keys list --home $EQ_PROVIDER_HOME --output json | jq -r '.[] | select(.name=="malval_det").address')

echo "> Fund new validator."
$CHAIN_BINARY tx bank send $WALLET_1 $malval_det $FUND_AMOUNT$DENOM --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y --home $HOME_1 | jq '.'

echo "> Setting up provider service."

sudo touch /etc/systemd/system/$EQ_PROVIDER_SERVICE
echo "[Unit]"                               | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE
echo "Description=Gaia service"             | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "ExecStart=$HOME/go/bin/$CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $EQ_PROVIDER_HOME" | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$EQ_PROVIDER_SERVICE -a

echo "Starting provider service..."
sudo systemctl enable $EQ_PROVIDER_SERVICE --now

sleep 30
# journalctl -u $EQ_PROVIDER_SERVICE

# $CHAIN_BINARY q block --home $EQ_PROVIDER_HOME | jq '.'
echo "> New provider node status:"
curl -s http://localhost:$EQ_PROV_RPC_PORT/status
curl -s http://localhost:$EQ_PROV_RPC_PORT/status | jq -r '.result.sync_info'

total_before=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.total')
echo "> Creating validator."
pubkey=$($CHAIN_BINARY tendermint show-validator --home $EQ_PROVIDER_HOME)
jq --argjson PUBKEY "$pubkey" '.pubkey |= $PUBKEY' templates/create-validator.json > validator.json
jq --arg AMOUNT "$STAKE_AMOUNT$DENOM" '.amount |= $AMOUNT' validator.json > validator-stake.json
mv validator-stake.json validator.json
jq '.' validator.json
$CHAIN_BINARY tx staking create-validator validator.json \
--gas auto \
--gas-adjustment $GAS_ADJUSTMENT \
--gas-prices $GAS_PRICE$DENOM \
--from $malval_det \
--home $EQ_PROVIDER_HOME -y

sleep $(($COMMIT_TIMEOUT*5))
$CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq '.'

echo "Setting up consumer node..."
$CONSUMER_CHAIN_BINARY config chain-id $CONSUMER_CHAIN_ID --home $EQ_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config keyring-backend test --home $EQ_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config node tcp://localhost:$EQ_CON_RPC_PORT_1 --home $EQ_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY init malval_det --chain-id $CONSUMER_CHAIN_ID --home $EQ_CONSUMER_HOME_1

echo "Getting patched genesis file..."
cp $CONSUMER_HOME_1/config/genesis.json $EQ_CONSUMER_HOME_1/config/genesis.json

echo "Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0$CONSUMER_DENOM\"^" $EQ_CONSUMER_HOME_1/config/app.toml
# Enable API
toml set --toml-path $EQ_CONSUMER_HOME_1/config/app.toml api.enable true
# Set different ports for api
toml set --toml-path $EQ_CONSUMER_HOME_1/config/app.toml api.address "tcp://0.0.0.0:$EQ_CON_API_PORT_1"
# Set different ports for grpc
toml set --toml-path $EQ_CONSUMER_HOME_1/config/app.toml grpc.address "0.0.0.0:$EQ_CON_GRPC_PORT_1"
# Turn off grpc web
toml set --toml-path $EQ_CONSUMER_HOME_1/config/app.toml grpc-web.enable false
# config.toml
# Set different ports for rpc
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml rpc.laddr "tcp://0.0.0.0:$EQ_CON_RPC_PORT_1"
# Set different ports for rpc pprof
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml rpc.pprof_laddr "localhost:$EQ_CON_PPROF_PORT_1"
# Set different ports for p2p
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml p2p.laddr "tcp://0.0.0.0:$EQ_CON_P2P_PORT_1"
echo "Set no strict address book rules..."
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml p2p.addr_book_strict false
# Allow duplicate IPs in p2p
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml p2p.allow_duplicate_ip true
echo "Setting persistent peer..."
CON2_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_2)
CON2_PEER="$CON2_NODE_ID@localhost:$CON2_P2P_PORT"
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml p2p.persistent_peers "$CON2_PEER"
echo "Setting a short commit timeout..."
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
# Set fast_sync to false - or block_sync for ICS v3
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml fast_sync false
toml set --toml-path $EQ_CONSUMER_HOME_1/config/config.toml block_sync false

echo "Setting up services..."

sudo touch /etc/systemd/system/$EQ_CONSUMER_SERVICE_1
echo "[Unit]"                               | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1
echo "Description=Consumer service"       | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "User=$USER"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $EQ_CONSUMER_HOME_1" | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "Restart=no"                       | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_1 -a

sudo touch /etc/systemd/system/$EQ_CONSUMER_SERVICE_2
echo "[Unit]"                               | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2
echo "Description=Consumer service"       | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "User=$USER"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $EQ_CONSUMER_HOME_2" | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "Restart=no"                       | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$EQ_CONSUMER_SERVICE_2 -a

echo "Starting consumer service..."
sudo systemctl enable $EQ_CONSUMER_SERVICE_1 --now

sleep 30
journalctl -u $EQ_CONSUMER_SERVICE_1

echo "> Submitting opt-in transaction."
key=$($CONSUMER_CHAIN_BINARY tendermint show-validator --home $EQ_CONSUMER_HOME_1)
echo "Consumer key: $key"
echo "Consumer ID: $CONSUMER_ID"
txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $key --from $malval_det --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $EQ_PROVIDER_HOME -y -o json | jq -r '.txhash')
sleep $COMMIT_TIMEOUT
echo "> txhash: $txhash"
echo "> Opt-in tx result:"
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

sleep 30
echo "> EQ Consumer key:"
$CHAIN_BINARY q provider validator-consumer-key $CONSUMER_ID $($CHAIN_BINARY tendermint show-address --home $EQ_PROVIDER_HOME) --home $HOME_1
echo "> EQ Consumer address:"
$CONSUMER_CHAIN_BINARY tendermint show-address --home $EQ_CONSUMER_HOME_1
echo "> EQ Consumer address (hex format):"
jq '.address' $EQ_CONSUMER_HOME_1/config/priv_validator_key.json

echo "> Check validator is in the consumer chain."
total_after=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.total')
diff=$(( $total_after - $total_before ))

if [ $diff == 1 ]; then
  echo "Validator created!"
else
  echo "Validator not created."
  exit 1
fi

val_bytes=$($CHAIN_BINARY keys parse $malval_det --output json | jq -r '.bytes')
eq_valoper=$($CHAIN_BINARY keys parse $val_bytes --output json | jq -r '.formats[2]')
echo "Validator address: $eq_valoper"

echo "> Consumer block from double-signing validator node 1:"
$CONSUMER_CHAIN_BINARY q block --home $EQ_CONSUMER_HOME_1 | jq '.'


echo "> Unbonding from validator."
$CHAIN_BINARY tx staking unbond $eq_valoper $UNBOND_AMOUNT$DENOM --from $malval_det --home $EQ_PROVIDER_HOME --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Redelegating from validator."
$CHAIN_BINARY tx staking redelegate $eq_valoper $VALOPER_3 $REDELEGATE_AMOUNT$DENOM --from $malval_det --home $EQ_PROVIDER_HOME --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y
sleep $(($COMMIT_TIMEOUT*2))

start_tokens=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$eq_valoper" '.validators[] | select(.operator_address==$oper).tokens')
start_unbonding=$($CHAIN_BINARY q staking unbonding-delegations-from $eq_valoper --home $HOME_1 -o json | jq -r '.unbonding_responses[0].entries[0].balance')
start_redelegation_dest=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$VALOPER_3" '.validators[] | select(.operator_address==$oper).tokens')

echo "Attempting to double sign..."

# Stop whale
echo "Stopping whale validator..."
sudo systemctl stop $CONSUMER_SERVICE_1
sudo systemctl stop $CONSUMER_SERVICE_2
sudo systemctl stop $CONSUMER_SERVICE_3
sleep 5

# Stop validator
sudo systemctl stop $EQ_CONSUMER_SERVICE_1
sleep 3
# Duplicate home folder
echo "Duplicating home folder..."
cp -r $EQ_CONSUMER_HOME_1/ $EQ_CONSUMER_HOME_2/

CON3_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_3)
CON3_PEER="$CON3_NODE_ID@localhost:$CON3_P2P_PORT"
toml set --toml-path $EQ_CONSUMER_HOME_2/config/config.toml p2p.persistent_peers "$CON3_PEER"

# Update ports
toml set --toml-path $EQ_CONSUMER_HOME_2/config/app.toml api.address "tcp://0.0.0.0:$EQ_CON_API_PORT_2"
# Set different ports for grpc
toml set --toml-path $EQ_CONSUMER_HOME_2/config/app.toml grpc.address "0.0.0.0:$EQ_CON_GRPC_PORT_2"
# config.toml
# Set different ports for rpc
toml set --toml-path $EQ_CONSUMER_HOME_2/config/config.toml rpc.laddr "tcp://0.0.0.0:$EQ_CON_RPC_PORT_2"
# Set different ports for rpc pprof
toml set --toml-path $EQ_CONSUMER_HOME_2/config/config.toml rpc.pprof_laddr "localhost:$EQ_CON_PPROF_PORT_2"
# Set different ports for p2p
toml set --toml-path $EQ_CONSUMER_HOME_2/config/config.toml p2p.laddr "tcp://0.0.0.0:$EQ_CON_P2P_PORT_2"

# Wipe the state and address books
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $EQ_CONSUMER_HOME_1/data/priv_validator_state.json
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $EQ_CONSUMER_HOME_2/data/priv_validator_state.json
echo "{}" > $EQ_CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $EQ_CONSUMER_HOME_1/config/addrbook.json

# Start duplicate node
echo "> Starting second node."
sudo systemctl enable $EQ_CONSUMER_SERVICE_2 --now
# sleep 10

# Start original node
echo "> Starting first node."
sudo systemctl start $EQ_CONSUMER_SERVICE_1
sleep 10

echo "{}" > $CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_3/config/addrbook.json

# Restart whale
echo "> Restarting whale validator."
sudo systemctl start $CONSUMER_SERVICE_2
sudo systemctl start $CONSUMER_SERVICE_3
sleep 60
sudo systemctl start $CONSUMER_SERVICE_1
echo "> Restarting Hermes."
sudo systemctl restart $RELAYER
sleep 180

# Restart nodes again
echo "Restarting nodes again..."
sudo systemctl stop $CONSUMER_SERVICE_1
sudo systemctl stop $CONSUMER_SERVICE_2
sudo systemctl stop $CONSUMER_SERVICE_3
sudo systemctl stop $EQ_CONSUMER_SERVICE_1
sudo systemctl stop $EQ_CONSUMER_SERVICE_2
sleep 2
# Wipe the state and address books
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $EQ_CONSUMER_HOME_1/data/priv_validator_state.json
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $EQ_CONSUMER_HOME_2/data/priv_validator_state.json
echo "{}" > $EQ_CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $EQ_CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_3/config/addrbook.json
sudo systemctl start $CONSUMER_SERVICE_2
sudo systemctl start $CONSUMER_SERVICE_3
sudo systemctl start $EQ_CONSUMER_SERVICE_1
sudo systemctl start $EQ_CONSUMER_SERVICE_2
sleep 60
sudo systemctl start $CONSUMER_SERVICE_1
echo "> Restarting Hermes."
sudo systemctl restart $RELAYER
sleep 180

echo "> Node 1:"
journalctl -u $EQ_CONSUMER_SERVICE_1 | tail -n 10
echo "> Node 2:"
journalctl -u $EQ_CONSUMER_SERVICE_2 | tail -n 10

echo "> Consumer chain evidence:"
$CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq '.'

consensus_address=$($CONSUMER_CHAIN_BINARY tendermint show-address --home $EQ_CONSUMER_HOME_1)
validator_check=$($CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq '.' | grep $consensus_address)
echo $validator_check
if [ -z "$validator_check" ]; then
  echo "No equivocation evidence found."
  exit 1
else
  echo "Equivocation evidence found!"
fi

echo "> Collecting infraction height."
height=$($CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq -r '.evidence[0].height')
echo "> Evidence height: $height"

echo "> Collecting evidence around the infraction height in consumer chain."
height_1=$(($height-1))
evidence_block=$(($height+1))
evidence_block_1=$(($height+2))
echo "> Consumer evidence at height $height_1:"
$CONSUMER_CHAIN_BINARY q block $height_1 --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $height:"
$CONSUMER_CHAIN_BINARY q block $height --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block:"
$CONSUMER_CHAIN_BINARY q block $evidence_block --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block_1:"
$CONSUMER_CHAIN_BINARY q block $evidence_block_1 --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block_1 (gaiad):"
$CHAIN_BINARY q block --type=height $evidence_block_1 --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY q block $evidence_block_1 --home $CONSUMER_HOME_1 | jq '.block.evidence.evidence[0].value' > evidence.json
echo "> Evidence JSON:"
jq '.' evidence.json

echo "***** EVIDENCE JSON MODIFICATION BEGINS *****"

echo "> Cast vote a height as integer."
jq '.vote_a.height |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast vote b height as integer."
jq '.vote_b.height |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote a block id hash."
hash=$(jq -r '.vote_a.block_id.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_a.block_id.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote a block id part hash."
hash=$(jq -r '.vote_a.block_id.parts.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_a.block_id.parts.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote b block id hash."
hash=$(jq -r '.vote_b.block_id.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_b.block_id.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote b block id part hash."
hash=$(jq -r '.vote_b.block_id.parts.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_b.block_id.parts.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename vote_a parts key."
jq '.vote_a.block_id.parts as $p | .vote_a.block_id.part_set_header = $p | del(.vote_a.block_id.parts)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename vote_b parts key."
jq '.vote_b.block_id.parts as $p | .vote_b.block_id.part_set_header = $p | del(.vote_b.block_id.parts)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json
jq '.' evidence.json

echo "> Base64 encode vote_a val address."
addr=$(jq -r '.vote_a.validator_address' evidence.json | xxd -r -p | base64)
echo "Base64-encoded: $addr"
jq --arg ADDR "$addr" '.vote_a.validator_address |= $ADDR' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote_b val address."
addr=$(jq -r '.vote_b.validator_address' evidence.json | xxd -r -p | base64)
echo "Base64-encoded: $addr"
jq --arg ADDR "$addr" '.vote_b.validator_address |= $ADDR' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename total voting power."
jq '.TotalVotingPower as $p | .total_voting_power = $p | del(.TotalVotingPower)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename validator power key."
jq '.ValidatorPower as $p | .validator_power = $p | del(.ValidatorPower)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename timestamp key."
jq '.Timestamp as $p | .timestamp = $p | del(.Timestamp)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast total voting power as integer."
jq '.total_voting_power |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast validator power as integer."
jq '.validator_power |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

jq '.' evidence.json

echo "***** EVIDENCE JSON MODIFICATION ENDS *****"

echo "> IBC header signatures at height $(($height-2))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height-2)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height-1))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height-1)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height+1))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height+1)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height+2))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height+2)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'


echo "> Collecting IBC header at infraction height in consumer chain."
$CONSUMER_CHAIN_BINARY q ibc client header --height $height --home $CONSUMER_HOME_1 -o json | jq '.' > ibc-header.json
echo "> IBC header JSON:"
jq '.' ibc-header.json

echo "***** IBC HEADER JSON MODIFICATION BEGINS *****"

echo "> Cast header height to integer."
jq '.signed_header.header.height |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast commit height to integer."
jq '.signed_header.commit.height |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Replace BLOCK_ID_FLAG_COMMIT with 2."
sed "s%\"BLOCK_ID_FLAG_COMMIT\"%2%g" ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Replace BLOCK_ID_FLAG_NIL with 3."
sed "s%\"BLOCK_ID_FLAG_NIL\"%3%g" ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast validators' voting power to integer."
jq '.validator_set.validators[].voting_power |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast validators' proposer priority to integer."
jq '.validator_set.validators[].proposer_priority |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast proposer's voting power to integer."
jq '.validator_set.proposer.voting_power |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast proposer's proposer priority to integer."
jq '.validator_set.proposer.proposer_priority |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Remove total_voting_power."
jq 'del(.validator_set.total_voting_power)' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Remove revision_number."
jq 'del(.trusted_height.revision_number)' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

jq '.' ibc-header.json

echo "***** IBC HEADER JSON MODIFICATION ENDS *****"


echo "> Submitting evidence."
txhash=$($CHAIN_BINARY tx provider submit-consumer-double-voting $CONSUMER_ID evidence.json ibc-header.json \
    --from $WALLET_1  --home $HOME_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
echo "> Evidence submission tx:"
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

# sudo systemctl enable hermes-evidence --now

# echo "Wait for evidence to reach the provider chain..."
# sleep 60

# journalctl -u hermes-evidence
echo "> Wait for validator to be removed from validator set."
sleep $(($COMMIT_TIMEOUT*2))
echo "> Signing infos:"
$CHAIN_BINARY q slashing signing-infos --home $HOME_1 -o json | jq '.'
echo "> Signing info:"
$CHAIN_BINARY q slashing signing-info $($CHAIN_BINARY tendermint show-validator --home $EQ_PROVIDER_HOME) --home $HOME_1 -o json | jq '.'
echo "> Validators:"
$CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq '.'

status=$($CHAIN_BINARY q slashing signing-info $($CHAIN_BINARY tendermint show-validator --home $EQ_PROVIDER_HOME) --home $HOME_1 -o json | jq '.val_signing_info.tombstoned')
echo "Status: $status"
if [ $status == "true" ]; then
  echo "Success: validator has been tombstoned!"
else
  echo "Failure: validator was not tombstoned."
  exit 1
fi

echo "Slashing checks:"
end_tokens=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$eq_valoper" '.validators[] | select(.operator_address==$oper).tokens')
end_unbonding=$($CHAIN_BINARY q staking unbonding-delegations-from $eq_valoper --home $HOME_1 -o json | jq -r '.unbonding_responses[0].entries[0].balance')
end_redelegation_dest=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$VALOPER_3" '.validators[] | select(.operator_address==$oper).tokens')

echo "Validator tokens: $start_tokens -> $end_tokens"
echo "Unbonding delegations: $start_unbonding -> $end_unbonding"
echo "Redelegation recipient: $start_redelegation_dest -> $end_redelegation_dest"

expected_slashed_tokens=$(echo "$SLASH_FACTOR * $start_tokens" | bc -l)
expected_slashed_unbonding=$(echo "$SLASH_FACTOR * $start_unbonding" | bc -l)
expected_slashed_redelegation=$(echo "$SLASH_FACTOR * $REDELEGATE_AMOUNT" | bc -l)
expected_slashed_total=$(echo "$SLASH_FACTOR * ($start_tokens + $start_unbonding + $REDELEGATE_AMOUNT)" | bc -l)

bonded_tokens_slashed=$(echo "$start_tokens - $end_tokens" | bc)
unbonding_slashed=$(echo "$start_unbonding - $end_unbonding" | bc)
redelegation_dest_slashed=$(echo "$start_redelegation_dest - $end_redelegation_dest" | bc)
total_slashed=$(echo "$bonded_tokens_slashed + $unbonding_slashed + $redelegation_dest_slashed" | bc -l)
echo "Tokens slashed: $bonded_tokens_slashed, expected: $expected_slashed_tokens"
echo "Unbonding delegations slashed: $unbonding_slashed, expected: $expected_slashed_unbonding"
echo "Redelegations slashed: $redelegation_dest_slashed, expected: $expected_slashed_redelegation"
echo "Total slashed: $total_slashed, expected: $expected_slashed_total"

if [[ $total_slashed -ne ${expected_slashed_total%.*} ]]; then
  echo "Total slashed tokens does not match expected value."
  exit 1
else
  echo "Total slashed tokens: pass"
fi

if [[ $bonded_tokens_slashed -ne ${expected_slashed_tokens%.*} ]]; then
  echo "Slashed bonded tokens does not match expected value."
  exit 1
else
  echo "Slashed bonded tokens: pass"
fi

if [[ $unbonding_slashed -ne ${expected_slashed_unbonding%.*} ]]; then
  echo "Slashed unbonding tokens does not match expected value."
  exit 1
else
  echo "Slashed unbonding tokens: pass"
fi

if [[ $redelegation_dest_slashed -ne ${expected_slashed_redelegation%.*} ]]; then
  echo "Slashed redelegation tokens does not match expected value."
  exit 1
else
  echo "Slashed redelegation tokens: pass"
fi

sudo systemctl disable $EQ_PROVIDER_SERVICE --now
sudo systemctl disable $EQ_CONSUMER_SERVICE_1 --now
sudo systemctl disable $EQ_CONSUMER_SERVICE_2 --now
rm -rf $EQ_PROVIDER_HOME
rm -rf $EQ_CONSUMER_HOME_1
rm -rf $EQ_CONSUMER_HOME_2
sudo rm /etc/systemd/system/$EQ_PROVIDER_SERVICE
sudo rm /etc/systemd/system/$EQ_CONSUMER_SERVICE_1
sudo rm /etc/systemd/system/$EQ_CONSUMER_SERVICE_2