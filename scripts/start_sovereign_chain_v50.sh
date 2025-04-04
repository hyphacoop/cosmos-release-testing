#!/bin/bash
# 1. Set up a three-validator sovereign chain.

echo "> Installing Binary."
wget $CHAIN_BINARY_URL -O $HOME/go/bin/$CONSUMER_CHAIN_BINARY -q
chmod +x $HOME/go/bin/$CONSUMER_CHAIN_BINARY

# Initialize home directories
echo "Initializing node homes..."
$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON1_RPC_PORT --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY init $MONIKER_1 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1

$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON2_RPC_PORT --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY init $MONIKER_2 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_2

$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON3_RPC_PORT --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY init $MONIKER_3 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_3

# Create self-delegation accounts
echo $MNEMONIC_1 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_1 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_2 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_2 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_3 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_3 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_4 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_4 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_5 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_5 --keyring-backend test --home $CONSUMER_HOME_1 --recover

echo "Setting denom to $CONSUMER_DENOM..."
jq -r --arg DENOM "$CONSUMER_DENOM" '.app_state.crisis.constant_fee.denom |= $DENOM' $CONSUMER_HOME_1/config/genesis.json > crisis.json
jq -r --arg DENOM "$CONSUMER_DENOM" '.app_state.gov.params.min_deposit[0].denom |= $DENOM' crisis.json > min_deposit.json
jq -r --arg DENOM "$CONSUMER_DENOM" '.app_state.mint.params.mint_denom |= $DENOM' min_deposit.json > mint.json
jq -r --arg DENOM "$CONSUMER_DENOM" '.app_state.staking.params.bond_denom |= $DENOM' mint.json > bond_denom.json
cp bond_denom.json $CONSUMER_HOME_1/config/genesis.json

$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_1 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_2 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_3 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_4 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_5 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1

echo "Creating and collecting gentxs..."
mkdir -p $CONSUMER_HOME_1/config/gentx
VAL1_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_1)
VAL2_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_2)
VAL3_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_3)
$CONSUMER_CHAIN_BINARY genesis gentx $MONIKER_1 $VAL1_STAKE$CONSUMER_DENOM --pubkey "$($CONSUMER_CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_1)" --node-id $VAL1_NODE_ID --moniker $MONIKER_1 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1 --output-document $CONSUMER_HOME_1/config/gentx/$MONIKER_1-gentx.json
$CONSUMER_CHAIN_BINARY genesis gentx $MONIKER_2 $VAL2_STAKE$CONSUMER_DENOM --pubkey "$($CONSUMER_CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_2)" --node-id $VAL2_NODE_ID --moniker $MONIKER_2 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1 --output-document $CONSUMER_HOME_1/config/gentx/$MONIKER_2-gentx.json
$CONSUMER_CHAIN_BINARY genesis gentx $MONIKER_3 $VAL3_STAKE$CONSUMER_DENOM --pubkey "$($CONSUMER_CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_3)" --node-id $VAL3_NODE_ID --moniker $MONIKER_3 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1 --output-document $CONSUMER_HOME_1/config/gentx/$MONIKER_3-gentx.json
$CONSUMER_CHAIN_BINARY genesis collect-gentxs --home $CONSUMER_HOME_1

echo "Patching genesis file for fast governance..."
jq -r ".app_state.gov.params.voting_period = \"$VOTING_PERIOD\"" $CONSUMER_HOME_1/config/genesis.json  > ./voting.json
jq -r ".app_state.gov.params.min_deposit[0].amount = \"1\"" ./voting.json > ./gov.json

cp gov.json $CONSUMER_HOME_1/config/genesis.json

# echo "Setting slashing window to 10..."
jq -r --arg SLASH "10" '.app_state.slashing.params.signed_blocks_window |= $SLASH' $CONSUMER_HOME_1/config/genesis.json > ./slashing.json
jq -r '.app_state.slashing.params.downtime_jail_duration |= "5s"' slashing.json > slashing-2.json
mv slashing-2.json $CONSUMER_HOME_1/config/genesis.json

echo "Set max block gas to 100_000_000."
jq -r '.consensus.params.block.max_gas = "100000000"' $CONSUMER_HOME_1/config/genesis.json > block-max-gas.json
mv block-max-gas.json $CONSUMER_HOME_1/config/genesis.json

echo "GENESIS FILE:"
jq '.' $CONSUMER_HOME_1/config/genesis.json

echo "Copying genesis file to other nodes..."
cp $CONSUMER_HOME_1/config/genesis.json $CONSUMER_HOME_2/config/genesis.json 
cp $CONSUMER_HOME_1/config/genesis.json $CONSUMER_HOME_3/config/genesis.json 

echo "Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE$CONSUMER_DENOM\"^" $CONSUMER_HOME_1/config/app.toml
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE$CONSUMER_DENOM\"^" $CONSUMER_HOME_2/config/app.toml
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE$CONSUMER_DENOM\"^" $CONSUMER_HOME_3/config/app.toml

# Enable API
toml set --toml-path $CONSUMER_HOME_1/config/app.toml api.enable true
toml set --toml-path $CONSUMER_HOME_2/config/app.toml api.enable true
toml set --toml-path $CONSUMER_HOME_3/config/app.toml api.enable true

# Set different ports for api
toml set --toml-path $CONSUMER_HOME_1/config/app.toml api.address "tcp://0.0.0.0:$CON1_API_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/app.toml api.address "tcp://0.0.0.0:$CON2_API_PORT"
toml set --toml-path $CONSUMER_HOME_3/config/app.toml api.address "tcp://0.0.0.0:$CON3_API_PORT"

# Set different ports for grpc
toml set --toml-path $CONSUMER_HOME_1/config/app.toml grpc.address "0.0.0.0:$CON1_GRPC_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/app.toml grpc.address "0.0.0.0:$CON2_GRPC_PORT"
toml set --toml-path $CONSUMER_HOME_3/config/app.toml grpc.address "0.0.0.0:$CON3_GRPC_PORT"

# Turn off grpc web
toml set --toml-path $CONSUMER_HOME_1/config/app.toml grpc-web.enable false
toml set --toml-path $CONSUMER_HOME_2/config/app.toml grpc-web.enable false
toml set --toml-path $CONSUMER_HOME_3/config/app.toml grpc-web.enable false

# config.toml
# Set log level to debug
# toml set --toml-path $CONSUMER_HOME_1/config/config.toml log_level "debug"

# Set different ports for rpc
toml set --toml-path $CONSUMER_HOME_1/config/config.toml rpc.laddr "tcp://0.0.0.0:$CON1_RPC_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml rpc.laddr "tcp://0.0.0.0:$CON2_RPC_PORT"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml rpc.laddr "tcp://0.0.0.0:$CON3_RPC_PORT"

# Set different ports for rpc pprof
toml set --toml-path $CONSUMER_HOME_1/config/config.toml rpc.pprof_laddr "localhost:$CON1_PPROF_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml rpc.pprof_laddr "localhost:$CON2_PPROF_PORT"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml rpc.pprof_laddr "localhost:$CON3_PPROF_PORT"

# Set different ports for p2p
toml set --toml-path $CONSUMER_HOME_1/config/config.toml p2p.laddr "tcp://0.0.0.0:$CON1_P2P_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml p2p.laddr "tcp://0.0.0.0:$CON2_P2P_PORT"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml p2p.laddr "tcp://0.0.0.0:$CON3_P2P_PORT"

# Allow duplicate IPs in p2p
toml set --toml-path $CONSUMER_HOME_1/config/config.toml p2p.allow_duplicate_ip true
toml set --toml-path $CONSUMER_HOME_2/config/config.toml p2p.allow_duplicate_ip true
toml set --toml-path $CONSUMER_HOME_3/config/config.toml p2p.allow_duplicate_ip true

echo "Setting a short commit timeout..."
seconds=s
toml set --toml-path $CONSUMER_HOME_1/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"

# Set persistent peers
echo "Setting persistent peers..."
VAL2_PEER="$VAL2_NODE_ID@localhost:$CON2_P2P_PORT"
VAL3_PEER="$VAL3_NODE_ID@localhost:$CON3_P2P_PORT"
toml set --toml-path $CONSUMER_HOME_1/config/config.toml p2p.persistent_peers "$VAL2_PEER,$VAL3_PEER"

toml set --toml-path $CONSUMER_HOME_1/config/config.toml p2p.addr_book_strict false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml p2p.addr_book_strict false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml p2p.addr_book_strict false


# Set fast_sync to false
toml set --toml-path $CONSUMER_HOME_1/config/config.toml block_sync false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml block_sync false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml block_sync false
toml set --toml-path $CONSUMER_HOME_1/config/config.toml fast_sync false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml fast_sync false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml fast_sync false

echo "Setting up services..."

sudo touch /etc/systemd/system/$CONSUMER_SERVICE_1
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1
echo "Description=Gaia service"             | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $CONSUMER_HOME_1" | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a

sudo touch /etc/systemd/system/$CONSUMER_SERVICE_2
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2
echo "Description=Gaia service"             | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $CONSUMER_HOME_2" | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a

echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a

sudo touch /etc/systemd/system/$CONSUMER_SERVICE_3
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3
echo "Description=Gaia service"             | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $CONSUMER_HOME_3" | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a

echo ""                                     | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a

sudo cat /etc/systemd/system/$CONSUMER_SERVICE_1

sudo systemctl daemon-reload
sudo systemctl enable $CONSUMER_SERVICE_1 --now
sudo systemctl enable $CONSUMER_SERVICE_2 --now
sudo systemctl enable $CONSUMER_SERVICE_3 --now
