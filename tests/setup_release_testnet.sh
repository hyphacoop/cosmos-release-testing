#!/bin/bash
# Set up a Gaia service to join the Cosmos Hub public testnet.

# Configuration
# You should only have to modify the values in this block
# ***
NODE_HOME=/home/runner/release
NODE_MONIKER=public-testnet
SERVICE_NAME=gaiad
GAIA_VERSION=v14.1.0
CHAIN_BINARY_URL=https://github.com/cosmos/gaia/releases/download/$GAIA_VERSION/gaiad-$GAIA_VERSION-linux-amd64
STATE_SYNC=true
GAS_PRICE=0.005uatom
# ***

CHAIN_BINARY='gaiad'
CHAIN_ID=theta-testnet-001
GENESIS_ZIPPED_URL=https://github.com/cosmos/testnets/raw/master/public/genesis.json.gz
SEEDS="639d50339d7045436c756a042906b9a69970913f@seed-01.theta-testnet.polypore.xyz:26656,3e506472683ceb7ed75c1578d092c79785c27857@seed-02.theta-testnet.polypore.xyz:26656"
SYNC_RPC_1=https://rpc.state-sync-01.theta-testnet.polypore.xyz:443
SYNC_RPC_2=https://rpc.state-sync-02.theta-testnet.polypore.xyz:443
SYNC_RPC_SERVERS="$SYNC_RPC_1,$SYNC_RPC_2"

# Install wget and jq
# sudo apt-get install curl jq wget -y

# Install Gaia binary
echo "Installing Gaia..."
mkdir -p /home/runner/go/bin
wget $CHAIN_BINARY_URL -O /home/runner/go/bin/$CHAIN_BINARY
chmod +x /home/runner/go/bin/$CHAIN_BINARY

# Initialize home directory
echo "Initializing $NODE_HOME..."
rm -rf $NODE_HOME
$CHAIN_BINARY config chain-id $CHAIN_ID --home $NODE_HOME
$CHAIN_BINARY config keyring-backend test --home $NODE_HOME
$CHAIN_BINARY init $NODE_MONIKER --chain-id $CHAIN_ID --home $NODE_HOME
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE\"^" $NODE_HOME/config/app.toml
sed -i -e "/seeds =/ s^= .*^= \"$SEEDS\"^" $NODE_HOME/config/config.toml

if $STATE_SYNC ; then
    echo "Configuring state sync..."
    CURRENT_BLOCK=$(curl -s $SYNC_RPC_1/block | jq -r '.result.block.header.height')
    TRUST_HEIGHT=$[$CURRENT_BLOCK-1000]
    TRUST_BLOCK=$(curl -s $SYNC_RPC_1/block\?height\=$TRUST_HEIGHT)
    TRUST_HASH=$(echo $TRUST_BLOCK | jq -r '.result.block_id.hash')
    sed -i -e '/enable =/ s/= .*/= true/' $NODE_HOME/config/config.toml
    sed -i -e '/trust_period =/ s/= .*/= "8h0m0s"/' $NODE_HOME/config/config.toml
    sed -i -e "/trust_height =/ s/= .*/= $TRUST_HEIGHT/" $NODE_HOME/config/config.toml
    sed -i -e "/trust_hash =/ s/= .*/= \"$TRUST_HASH\"/" $NODE_HOME/config/config.toml
    sed -i -e "/rpc_servers =/ s^= .*^= \"$SYNC_RPC_SERVERS\"^" $NODE_HOME/config/config.toml
else
    echo "Skipping state sync..."
fi

# Replace genesis file
echo "Downloading genesis file..."
wget $GENESIS_ZIPPED_URL -q
gunzip genesis.json.gz -f
mv genesis.json $NODE_HOME/config/genesis.json
