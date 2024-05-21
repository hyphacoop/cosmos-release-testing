#!/bin/bash
# 1. Set up a two-validator provider chain.
set -ex
source ~/env/bin/activate

echo "Building gaia"
GAIA_BRANCH="release/${START_VERSION%%.*}.x"
git clone https://github.com/cosmos/gaia.git
cd gaia
git checkout $GAIA_BRANCH
make build BUILD_TAGS="-tag unsafe_start_local_validator"
cp build/$CHAIN_BINARY $HOME/go/bin/$CHAIN_BINARY
cd ..


# Download archived home directory
echo "Initializing node homes..."
mkdir -p $HOME_1 
$CHAIN_BINARY tendermint unsafe-reset-all --home $HOME_1
echo "Downloading and extracting archived state"
curl -o - -L $ARCHIVE_URL  | lz4 -c -d - | tar -x -C $HOME_1
curl -Ls https://ss.cosmos.nodestake.org/genesis.json > $HOME_1/config/genesis.json
curl -Ls https://ss.cosmos.nodestake.org/addrbook.json > $HOME_1/config/addrbook.json

echo "Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$DENOM\"^" $HOME_1/config/app.toml
# Enable API
toml set --toml-path $HOME_1/config/app.toml api.enable true
# Set different ports for api
toml set --toml-path $HOME_1/config/app.toml api.address "tcp://0.0.0.0:$VAL1_API_PORT"
# Set different ports for grpc
toml set --toml-path $HOME_1/config/app.toml grpc.address "0.0.0.0:$VAL1_GRPC_PORT"
# Turn off grpc web
toml set --toml-path $HOME_1/config/app.toml grpc-web.enable false
# config.toml
# Replace fast_sync with block_sync
sed -i -e "s\fast_sync\block_sync\g" $HOME_1/config/config.toml
# Set different ports for rpc
toml set --toml-path $HOME_1/config/config.toml rpc.laddr "tcp://0.0.0.0:$VAL1_RPC_PORT"
# Set different ports for rpc pprof
toml set --toml-path $HOME_1/config/config.toml rpc.pprof_laddr "localhost:$VAL1_PPROF_PORT"
# Set different ports for p2p
toml set --toml-path $HOME_1/config/config.toml p2p.laddr "tcp://0.0.0.0:$VAL1_P2P_PORT"
# Allow duplicate IPs in p2p
toml set --toml-path $HOME_1/config/config.toml p2p.allow_duplicate_ip true
# Set client ports for rpc
toml set --toml-path $HOME_1/config/client.toml node "tcp://localhost:$VAL1_RPC_PORT"
# Set client chain-id
toml set --toml-path $HOME_1/config/client.toml chain-id "$CHAIN_ID"

curl -L https://raw.githubusercontent.com/hyphacoop/cosmos-ansible/main/examples/validator-keys/validator-40/priv_validator_key.json > $HOME_1/config/priv_validator_key.json
pubkey=$(jq -r .pub_key.value $HOME_1/config/priv_validator_key.json)
privkey=$(jq -r .priv_key.value $HOME_1/config/priv_validator_key.json)

echo $MNEMONIC_1 | $CHAIN_BINARY keys add $MONIKER_1 --keyring-backend test --recover --home $HOME_1

echo "Setting up services..."
echo "Creating script for $CHAIN_BINARY"
echo "while true; do $HOME/go/bin/$CHAIN_BINARY testnet unsafe-start-local-validator --validator-operator '$VALOPER_1' --validator-pubkey '$pubkey' --accounts-to-fund '$WALLET_1' --validator-privkey '$privkey' --home '$HOME_1'; sleep 1; done" > $HOME/$PROVIDER_SERVICE_1.sh
chmod +x $HOME/$PROVIDER_SERVICE_1.sh

# Run service in screen session
if [ ! -d $HOME/artifact ]
then
    mkdir $HOME/artifact
fi

echo "Starting $CHAIN_BINARY"
screen -L -Logfile $HOME/artifact/$PROVIDER_SERVICE_1.log -S $PROVIDER_SERVICE_1 -d -m bash $HOME/$PROVIDER_SERVICE_1.sh
# set screen to flush log to 0
screen -r $PROVIDER_SERVICE_1 -p0 -X logfile flush 0
