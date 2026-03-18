#!/bin/bash

gaiad init fork-home --chain-id provider --home $FORK_HOME
toml set --toml-path $FORK_HOME/config/client.toml keyring-backend test
toml set --toml-path $FORK_HOME/config/app.toml minimum-gas-prices $GAS_PRICE
toml set --toml-path $FORK_HOME/config/app.toml api.enable true
toml set --toml-path $FORK_HOME/config/app.toml api.address tcp://localhost:1317
toml set --toml-path $FORK_HOME/config/app.toml grpc.address localhost:9090
toml set --toml-path $FORK_HOME/config/app.toml state-sync.snapshot-interval 0
toml set --toml-path $FORK_HOME/config/config.toml rpc.laddr tcp://127.0.0.1:26657
toml set --toml-path $FORK_HOME/config/config.toml rpc.pprof_laddr localhost:6060
toml set --toml-path $FORK_HOME/config/config.toml p2p.laddr tcp://0.0.0.0:26656

echo "> Copying snapshot."
cp -r $whale_home/data

echo "> Extracting snapshot."
lz4 -dc snapshot-latest-provider.tar.lz4  | tar -x -C .gaia-fork
PUBKEY=$(jq -r '.pub_key.value' .gaia-fork/config/priv_validator_key.json)
PRIVKEY=$(jq -r '.priv_key.value' .gaia-fork/config/priv_validator_key.json)
WALLET=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
VALIDATOR=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv

# Target: auto-select

# build/gaiad testnet unsafe-start-local-validator \
./gaiad-v27.0.0-fork testnet unsafe-start-local-validator \
--validator-operator="$VALIDATOR" \
--validator-pubkey="$PUBKEY" \
--validator-privkey="$PRIVKEY" \
--accounts-to-fund="$WALLET" \
--auto-find-target \
--home .gaia-fork | tee log.txt

