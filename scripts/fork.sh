#!/bin/bash

gaiad init fork-home --chain-id testnet --home $FORK_HOME
toml set --toml-path $FORK_HOME/config/client.toml keyring-backend test
toml set --toml-path $FORK_HOME/config/app.toml minimum-gas-prices $GAS_PRICE
toml set --toml-path $FORK_HOME/config/app.toml api.enable true
toml set --toml-path $FORK_HOME/config/app.toml api.address tcp://localhost:1317
toml set --toml-path $FORK_HOME/config/app.toml grpc.address localhost:9090
toml set --toml-path $FORK_HOME/config/app.toml state-sync.snapshot-interval 0
toml set --toml-path $FORK_HOME/config/config.toml rpc.laddr tcp://127.0.0.1:26657
toml set --toml-path $FORK_HOME/config/config.toml rpc.pprof_laddr localhost:6060
toml set --toml-path $FORK_HOME/config/config.toml p2p.laddr tcp://0.0.0.0:26656

rm -rf $FORK_HOME/data
rm -rf $FORK_HOME/wasm

echo "> Copying snapshot."
cp -r "$whale_home/data" "$FORK_HOME/data"
cp -r "$whale_home/wasm" "$FORK_HOME/wasm"

echo "> Whale data:"
ls $whale_home/data
echo "> Fork data:"
ls $FORK_HOME/data
echo "> Whale wasm:"
ls $whale_home/wasm
echo "> Fork wasm:"
ls $FORK_HOME/wasm

PUBKEY=$(jq -r '.pub_key.value' $FORK_HOME/config/priv_validator_key.json)
PRIVKEY=$(jq -r '.priv_key.value' $FORK_HOME/config/priv_validator_key.json)
WALLET=cosmos1ay4dpm0kjmvtpug28vgw5w32yyjxa5sp97pjqq
VALIDATOR=cosmosvaloper1ay4dpm0kjmvtpug28vgw5w32yyjxa5spq248vn

# echo "> Rolling back chain to ensure a clean state."
# $CHAIN_BINARY rollback --hard --home $FORK_HOME
echo "> Resetting validator state."
jq '.' $FORK_HOME/data/priv_validator_state.json
# Set height, round, and step to 0 to ensure a clean state for voting on the upgrade proposal
jq '.height="0" | .round=0 | .step=0' $FORK_HOME/data/priv_validator_state.json > $FORK_HOME/data/priv_validator_state.json.tmp && mv $FORK_HOME/data/priv_validator_state.json.tmp $FORK_HOME/data/priv_validator_state.json
jq 'del(.signature) | del(.signbytes)' $FORK_HOME/data/priv_validator_state.json > $FORK_HOME/data/priv_validator_state.json.tmp && mv $FORK_HOME/data/priv_validator_state.json.tmp $FORK_HOME/data/priv_validator_state.json
jq '.' $FORK_HOME/data/priv_validator_state.json

# Target: auto-select
# build/gaiad testnet unsafe-start-local-validator \
$FORK_BINARY testnet unsafe-start-local-validator \
--validator-operator="$VALIDATOR" \
--validator-pubkey="$PUBKEY" \
--validator-privkey="$PRIVKEY" \
--accounts-to-fund="$WALLET" \
--auto-find-target \
--home $FORK_HOME > fork.log 2>&1 &

FORK_PID=$!

echo "> Started fork process with PID: $FORK_PID"
sleep 30

echo "> Killing fork process with PID: $FORK_PID"
kill $FORK_PID
echo "> Fork process with PID: $FORK_PID has been killed"
cat fork.log
rm fork.log
