#!/bin/bash
# 1. Set up a two-validator provider chain.
set -e

source ~/env/bin/activate

# Copy val1's home to val2
cp -rp $HOME_1 $HOME_2

echo "[INFO]: Downloading validator-32 node keys"
curl -L https://raw.githubusercontent.com/hyphacoop/cosmos-ansible/main/examples/validator-keys/validator-32/priv_validator_key.json > $HOME_2/config/priv_validator_key.json
curl -L https://raw.githubusercontent.com/hyphacoop/cosmos-ansible/main/examples/validator-keys/validator-32/node_key.json > $HOME_2/config/node_key.json

echo "[INFO]: Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$DENOM\"^" $HOME_2/config/app.toml

# Enable API
toml set --toml-path $HOME_2/config/app.toml api.enable true

# Set different ports for api
toml set --toml-path $HOME_2/config/app.toml api.address "tcp://0.0.0.0:$VAL2_API_PORT"

# Set different ports for grpc
toml set --toml-path $HOME_2/config/app.toml grpc.address "0.0.0.0:$VAL2_GRPC_PORT"

# Turn off grpc web
toml set --toml-path $HOME_2/config/app.toml grpc-web.enable false

# config.toml
# Replace fast_sync with block_sync
sed -i -e "s\fast_sync\block_sync\g" $HOME_2/config/config.toml

# Set different ports for rpc
toml set --toml-path $HOME_2/config/config.toml rpc.laddr "tcp://0.0.0.0:$VAL2_RPC_PORT"

# Set different ports for rpc pprof
toml set --toml-path $HOME_2/config/config.toml rpc.pprof_laddr "localhost:$VAL2_PPROF_PORT"

# Set different ports for p2p
toml set --toml-path $HOME_2/config/config.toml p2p.laddr "tcp://0.0.0.0:$VAL2_P2P_PORT"

# Allow duplicate IPs in p2p
toml set --toml-path $HOME_2/config/config.toml p2p.allow_duplicate_ip true

# Set client ports for rpc
toml set --toml-path $HOME_2/config/client.toml node "tcp://localhost:$VAL2_RPC_PORT"

# Set client chain-id
toml set --toml-path $HOME_2/config/client.toml chain-id "$CHAIN_ID"

# Turn on Instrumentation
toml set --toml-path $HOME_2/config/config.toml instrumentation.prometheus true

# Turn on statesync
toml set --toml-path $HOME_2/config/app.toml state-sync.snapshot-interval --to-int 1000

# Set persistent_peer
val1_node_id=$(gaiad --home $HOME_1 tendermint show-node-id)
toml set --toml-path $HOME_2/config/config.toml p2p.persistent_peers "$val1_node_id@localhost:$VAL1_P2P_PORT"

# rm addrbook
rm $HOME_2/config/addrbook.json || true

# Create self-delegation accounts
val2_self_delegation=$($CHAIN_BINARY --home $HOME_2 keys add val2 --output json)
echo "[INFO] val2_self_delegation: $val2_self_delegation"
echo "VAL2_SELF_DELEGATION=$(echo $val2_self_delegation | jq -r '.address')" >> $GITHUB_ENV

echo "[INFO]: Setting up services..."
echo "[INFO]: Creating script for $CHAIN_BINARY"
echo "while true; do $HOME/go/bin/$CHAIN_BINARY start --home $HOME_2; sleep 1; done" > $HOME/$PROVIDER_SERVICE_2.sh
chmod +x $HOME/$PROVIDER_SERVICE_2.sh

# Run service in screen session
if [ ! -d $HOME/artifact ]
then
    mkdir $HOME/artifact
fi

echo "[INFO]: Starting $CHAIN_BINARY"
screen -L -Logfile $HOME/artifact/$PROVIDER_SERVICE_2.log -S $PROVIDER_SERVICE_2 -d -m bash $HOME/$PROVIDER_SERVICE_2.sh
# set screen to flush log to 0
screen -r $PROVIDER_SERVICE_2 -p0 -X logfile flush 0
