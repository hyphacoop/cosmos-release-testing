#!/bin/bash
# Initialize a consumer chain

echo "Running with $CONSUMER_CHAIN_BINARY."

# Initialize home directories
echo "Initializing consumer homes..."
$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON1_RPC_PORT --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY init $MONIKER_1 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_1
cat $CONSUMER_HOME_1/config/client.toml

$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON2_RPC_PORT --home $CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY init $MONIKER_2 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_2

$CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY config set client keyring-backend test --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY config set client node tcp://localhost:$CON3_RPC_PORT --home $CONSUMER_HOME_3
$CONSUMER_CHAIN_BINARY init $MONIKER_3 --chain-id $CONSUMER_CHAIN_ID --home $CONSUMER_HOME_3

echo "chains:"
$CHAIN_BINARY q provider list-consumer-chains --home $HOME_1 -o json | jq -r '.chains[]'
# client_id=$($CHAIN_BINARY q provider list-consumer-chains --home $HOME_1 -o json | jq -r --arg chain_id "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chain_id).client_id')
# echo "Client ID: $client_id"
# $CHAIN_BINARY q provider  consumer-id-from-client-id $client_id
# CONSUMER_ID=$($CHAIN_BINARY q provider  consumer-id-from-client-id $client_id)
echo "Consumer ID: $CONSUMER_ID"

echo "Submit key assignment tx..."
CON1_PUBKEY=$($CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_1)
CON2_PUBKEY=$($CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_2)
CON3_PUBKEY=$($CHAIN_BINARY tendermint show-validator --home $CONSUMER_HOME_3)
if [ $TOPN -eq "0" ]; then
    echo "Opting in with val1..."
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $CON1_PUBKEY --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y -o json | jq -r '.txhash')
    echo "opt-in tx: $txhash"
    sleep $(($COMMIT_TIMEOUT+2))
    $CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'
    echo "Opting in with val2..."
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $CON2_PUBKEY --from $WALLET_2 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y -o json | jq -r '.txhash')
    echo "opt-in tx: $txhash"
    sleep $(($COMMIT_TIMEOUT+2))
    $CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'
    echo "Opting in with val3..."
    txhash=$($CHAIN_BINARY tx provider opt-in $CONSUMER_ID $CON3_PUBKEY --from $WALLET_3 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y -o json | jq -r '.txhash')
    echo "opt-in tx: $txhash"
    sleep $(($COMMIT_TIMEOUT+2))
    $CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'
else
    $CHAIN_BINARY tx provider assign-consensus-key $CONSUMER_ID $CON1_PUBKEY --from $WALLET_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y
    sleep $(($COMMIT_TIMEOUT+2))
    $CHAIN_BINARY tx provider assign-consensus-key $CONSUMER_ID $CON2_PUBKEY --from $WALLET_2 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y
    sleep $(($COMMIT_TIMEOUT+2))
    $CHAIN_BINARY tx provider assign-consensus-key $CONSUMER_ID $CON3_PUBKEY --from $WALLET_3 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y
    sleep $(($COMMIT_TIMEOUT+2))
fi

# $CHAIN_BINARY tx provider assign-consensus-key $CONSUMER_CHAIN_ID $CON2_PUBKEY --from $WALLET_2 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y
# sleep $COMMIT_TIMEOUT
# $CHAIN_BINARY tx provider assign-consensus-key $CONSUMER_CHAIN_ID $CON3_PUBKEY --from $WALLET_3 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $HOME_1 -y
# sleep $COMMIT_TIMEOUT

$CHAIN_BINARY q provider list-consumer-chains --home $HOME_1
echo "val1 key in consumer:"
$CHAIN_BINARY q provider validator-consumer-key $CONSUMER_ID $($CHAIN_BINARY tendermint show-address --home $HOME_1) --home $HOME_1
echo "val2 key in consumer:"
$CHAIN_BINARY q provider validator-consumer-key $CONSUMER_ID $($CHAIN_BINARY tendermint show-address --home $HOME_2) --home $HOME_1
echo "val3 key in consumer:"
$CHAIN_BINARY q provider validator-consumer-key $CONSUMER_ID $($CHAIN_BINARY tendermint show-address --home $HOME_3) --home $HOME_1


# Update genesis file with right denom
# sed -i s%stake%$CONSUMER_DENOM%g $CONSUMER_HOME_1/config/genesis.json
jq --arg DENOM "$CONSUMER_DENOM" '.app_state.crisis.constant_fee.denom = $DENOM' $CONSUMER_HOME_1/config/genesis.json > genesis-1.json
mv genesis-1.json $CONSUMER_HOME_1/config/genesis.json

echo "Patching genesis for block max gas != -1..."
jq -r '.consensus_params.block.max_gas = "50000000"' $CONSUMER_HOME_1/config/genesis.json > consumer-gas.json
mv consumer-gas.json $CONSUMER_HOME_1/config/genesis.json

# Set slashing to $DOWNTIME_BLOCKS
jq -r --arg SLASH "$DOWNTIME_BLOCKS" '.app_state.slashing.params.signed_blocks_window |= $SLASH' $CONSUMER_HOME_1/config/genesis.json > consumer-slashing.json
jq -r '.app_state.slashing.params.downtime_jail_duration |= "10s"' consumer-slashing.json > consumer-slashing-2.json
mv consumer-slashing-2.json $CONSUMER_HOME_1/config/genesis.json

# Create self-delegation accounts
echo $MNEMONIC_1 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_1 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_2 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_2 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_3 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_3 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_5 | $CONSUMER_CHAIN_BINARY keys add $MONIKER_5 --keyring-backend test --home $CONSUMER_HOME_1 --recover
echo $MNEMONIC_RELAYER | $CONSUMER_CHAIN_BINARY keys add $MONIKER_RELAYER --keyring-backend test --home $CONSUMER_HOME_1 --recover

# Add funds to accounts
# $CONSUMER_CHAIN_BINARY add-genesis-account $MONIKER_1 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test
# $CONSUMER_CHAIN_BINARY add-genesis-account $MONIKER_5 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test
# $CONSUMER_CHAIN_BINARY add-genesis-account $MONIKER_RELAYER $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_1 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_5 $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test
$CONSUMER_CHAIN_BINARY genesis add-genesis-account $MONIKER_RELAYER $VAL_FUNDS$CONSUMER_DENOM --home $CONSUMER_HOME_1 --keyring-backend test

# Update genesis file with right denom
if [ "$CONSUMER_CHAIN_BINARY" == "strided" ]; then
    echo "Patching genesis file for Stride denom..."
    jq '.app_state.crisis.constant_fee.denom = "ustrd"' $CONSUMER_HOME_1/config/genesis.json > stride-genesis-1.json
    jq '.app_state.gov.params.min_deposit[0].denom = "ustrd"' stride-genesis-1.json > stride-genesis-2.json
    jq '.app_state.mint.params.mint_denom = "ustrd"' stride-genesis-2.json > stride-genesis-3.json
    jq '.app_state.staking.params.bond_denom = "ustrd"' stride-genesis-3.json > stride-genesis-4.json

    echo "Patching genesis file for Stride fast governance..."
    jq '(.app_state.epochs.epochs[] | select(.identifier=="day") ).duration = "120s"' stride-genesis-4.json  > stride-genesis-5.json
    jq '(.app_state.epochs.epochs[] | select(.identifier=="stride_epoch") ).duration = "120s"' stride-genesis-5.json  > stride-genesis-6.json
    jq '.app_state.gov.voting_params.voting_period = "30s"' stride-genesis-6.json  > stride-genesis-7.json
    jq '.app_state.gov.params.voting_period = "30s"' stride-genesis-7.json  > stride-genesis-8.json

elif [ "$CONSUMER_CHAIN_BINARY" == "neutrond" ]; then
    jq --arg DENOM "$CONSUMER_DENOM" -r '.app_state.globalfee.params.minimum_gas_prices[0] |= {"amount": "0.02", "denom": $DENOM}' $CONSUMER_HOME_1/config/genesis.json > consumer-globalfee.json
    mv consumer-globalfee.json $CONSUMER_HOME_1/config/genesis.json

    echo "Patching genesis for feemarket params..."
    jq -r '.app_state.feemarket.params.fee_denom |= "untrn"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-denom.json
    mv feemarket-denom.json $CONSUMER_HOME_1/config/genesis.json
    jq -r '.app_state.feemarket.params.min_base_gas_price |= "0.005"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-min-base.json
    mv feemarket-min-base.json $CONSUMER_HOME_1/config/genesis.json
    jq -r '.app_state.feemarket.state.base_gas_price |= "0.005"' $CONSUMER_HOME_1/config/genesis.json > ./feemarket-base.json
    mv feemarket-base.json $CONSUMER_HOME_1/config/genesis.json
fi

echo "Patching config files..."
# app.toml
# minimum_gas_prices
# sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$CONSUMER_DENOM\"^" $CONSUMER_HOME_1/config/app.toml
# sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$CONSUMER_DENOM\"^" $CONSUMER_HOME_2/config/app.toml
# sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0.0025$CONSUMER_DENOM\"^" $CONSUMER_HOME_3/config/app.toml
toml set --toml-path $CONSUMER_HOME_1/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE$CONSUMER_DENOM"
toml set --toml-path $CONSUMER_HOME_2/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE$CONSUMER_DENOM"
toml set --toml-path $CONSUMER_HOME_3/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE$CONSUMER_DENOM"

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

# Turn pex off
toml set --toml-path $CONSUMER_HOME_1/config/config.toml p2p.pex false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml p2p.pex false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml p2p.pex false


echo "Setting persistent peers..."
VAL1_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_1)
# VAL2_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_2)
# VAL3_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_3)
VAL1_PEER="$VAL1_NODE_ID@localhost:$CON1_P2P_PORT"
# VAL2_PEER="$VAL2_NODE_ID@localhost:$CON2_P2P_PORT"
# VAL3_PEER="$VAL3_NODE_ID@localhost:$CON3_P2P_PORT"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml p2p.persistent_peers "$VAL1_PEER"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml p2p.persistent_peers "$VAL1_PEER"

echo "Setting a short commit timeout..."
seconds=s
toml set --toml-path $CONSUMER_HOME_1/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"
toml set --toml-path $CONSUMER_HOME_2/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"
toml set --toml-path $CONSUMER_HOME_3/config/config.toml consensus.timeout_commit "$COMMIT_TIMEOUT$seconds"

# Set fast_sync to false - or block_sync for ICS v3
toml set --toml-path $CONSUMER_HOME_1/config/config.toml fast_sync false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml fast_sync false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml fast_sync false
toml set --toml-path $CONSUMER_HOME_1/config/config.toml block_sync false
toml set --toml-path $CONSUMER_HOME_2/config/config.toml block_sync false
toml set --toml-path $CONSUMER_HOME_3/config/config.toml block_sync false

echo "Setting up services..."

sudo rm /etc/systemd/system/$CONSUMER_SERVICE_1
sudo touch /etc/systemd/system/$CONSUMER_SERVICE_1
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1
echo "Description=Consumer service"         | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_1 -a
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

sudo rm /etc/systemd/system/$CONSUMER_SERVICE_2
sudo touch /etc/systemd/system/$CONSUMER_SERVICE_2
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2
echo "Description=Consumer service"         | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
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

sudo rm /etc/systemd/system/$CONSUMER_SERVICE_3
sudo touch /etc/systemd/system/$CONSUMER_SERVICE_3
echo "[Unit]"                               | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3
echo "Description=Consumer service"         | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_3 -a
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

sudo systemctl daemon-reload
