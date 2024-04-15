#!/bin/bash
# 1. Set up a one-validator chain 

# Initialize home directories
echo "Initializing node home..."
$CHAIN_BINARY_SECONDARY config chain-id $CHAIN_ID --home $CHAIN_HOME
$CHAIN_BINARY_SECONDARY config keyring-backend test --home $CHAIN_HOME
$CHAIN_BINARY_SECONDARY config node tcp://localhost:$RPC_PORT --home $CHAIN_HOME
$CHAIN_BINARY_SECONDARY init $MONIKER_1 --chain-id $CHAIN_ID --home $CHAIN_HOME

# Create self-delegation accounts
echo $MNEMONIC_1 | $CHAIN_BINARY_SECONDARY keys add $MONIKER_1 --keyring-backend test --home $CHAIN_HOME --recover
echo $MNEMONIC_RELAYER | $CHAIN_BINARY_SECONDARY keys add $MONIKER_RELAYER --keyring-backend test --home $CHAIN_HOME --recover

# Update genesis file with right denom
echo "Setting denom to $DENOM..."
jq -r --arg denom "$DENOM" '.app_state.crisis.constant_fee.denom |= $denom' $CHAIN_HOME/config/genesis.json > crisis.json
jq -r --arg denom "$DENOM" '.app_state.gov.params.min_deposit[0].denom |= $denom' crisis.json > min_deposit.json
jq -r --arg denom "$DENOM" '.app_state.mint.params.mint_denom |= $denom' min_deposit.json > mint.json
jq -r --arg denom "$DENOM" '.app_state.staking.params.bond_denom |= $denom' mint.json > bond_denom.json
jq -r --arg denom "$DENOM" '.app_state.provider.params.consumer_reward_denom_registration_fee.denom = $denom' bond_denom.json > reward_reg.json
cp reward_reg.json $CHAIN_HOME/config/genesis.json

# Add funds to accounts
$CHAIN_BINARY_SECONDARY genesis add-genesis-account $MONIKER_1 $VAL_FUNDS$DENOM --home $CHAIN_HOME
$CHAIN_BINARY_SECONDARY genesis add-genesis-account $MONIKER_RELAYER $VAL_FUNDS$DENOM --home $CHAIN_HOME

echo "Creating and collecting gentxs..."
mkdir -p $CHAIN_HOME/config/gentx
VAL1_NODE_ID=$($CHAIN_BINARY_SECONDARY tendermint show-node-id --home $CHAIN_HOME)
$CHAIN_BINARY_SECONDARY genesis gentx $MONIKER_1 $VAL1_STAKE$DENOM --pubkey "$($CHAIN_BINARY_SECONDARY tendermint show-validator --home $CHAIN_HOME)" --node-id $VAL1_NODE_ID --moniker $MONIKER_1 --chain-id $CHAIN_ID --home $CHAIN_HOME --output-document $CHAIN_HOME/config/gentx/$MONIKER_1-gentx.json
$CHAIN_BINARY_SECONDARY genesis collect-gentxs --home $CHAIN_HOME

echo "Patching genesis file for fast governance..."
jq -r ".app_state.gov.voting_params.voting_period = \"$VOTING_PERIOD\"" $CHAIN_HOME/config/genesis.json  > ./voting.json
jq -r ".app_state.gov.params.min_deposit[0].amount = \"1\"" ./voting.json > ./gov.json

# echo "Setting slashing window to 10..."
# jq -r --arg SLASH "10" '.app_state.slashing.params.signed_blocks_window |= $SLASH' ./gov.json > ./slashing.json
# jq -r '.app_state.slashing.params.downtime_jail_duration |= "5s"' slashing.json > slashing-2.json
# mv slashing-2.json $CHAIN_HOME/config/genesis.json

# echo "Patching genesis file for LSM params..."
# jq -r '.app_state.staking.params.validator_bond_factor = "10.000000000000000000"' slashing-2.json > lsm-1.json
# jq -r '.app_state.staking.params.global_liquid_staking_cap = "0.100000000000000000"' lsm-1.json > lsm-2.json
# jq -r '.app_state.staking.params.validator_liquid_staking_cap = "0.200000000000000000"' lsm-2.json > lsm-3.json

cat $CHAIN_HOME/config/genesis.json

echo "Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE$DENOM\"^" $CHAIN_HOME/config/app.toml

# Enable API
toml set --toml-path $CHAIN_HOME/config/app.toml api.enable true

# Set different ports for api
toml set --toml-path $CHAIN_HOME/config/app.toml api.address "tcp://0.0.0.0:$API_PORT"

# Set different ports for grpc
toml set --toml-path $CHAIN_HOME/config/app.toml grpc.address "0.0.0.0:$GRPC_PORT"

# Turn off grpc web
toml set --toml-path $CHAIN_HOME/config/app.toml grpc-web.enable false

# config.toml
# Set log level to debug
# toml set --toml-path $CHAIN_HOME/config/config.toml log_level "debug"

# Set different ports for rpc
toml set --toml-path $CHAIN_HOME/config/config.toml rpc.laddr "tcp://0.0.0.0:$RPC_PORT"

# Set different ports for rpc pprof
toml set --toml-path $CHAIN_HOME/config/config.toml rpc.pprof_laddr "localhost:$PPROF_PORT"

# Set different ports for p2p
toml set --toml-path $CHAIN_HOME/config/config.toml p2p.laddr "tcp://0.0.0.0:$P2P_PORT"

# Allow duplicate IPs in p2p
toml set --toml-path $CHAIN_HOME/config/config.toml p2p.allow_duplicate_ip true

echo "Setting a short commit timeout..."
seconds=s
toml set --toml-path $CHAIN_HOME/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"

# Set fast_sync to false
toml set --toml-path $CHAIN_HOME/config/config.toml block_sync false


echo "Setting up services..."

sudo touch /etc/systemd/system/$CHAIN_SERVICE
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CHAIN_SERVICE
echo "Description=Gaia service"             | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo ""                                     | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "ExecStart=$HOME/go/bin/$CHAIN_BINARY_SECONDARY start --x-crisis-skip-assert-invariants --home $CHAIN_HOME" | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo ""                                     | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$CHAIN_SERVICE -a

sudo cat /etc/systemd/system/$CHAIN_SERVICE

sudo systemctl daemon-reload
sudo systemctl enable $CHAIN_SERVICE --now
