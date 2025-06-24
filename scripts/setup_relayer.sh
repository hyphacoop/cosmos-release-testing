#!/bin/bash
# Set up a relayer

if [ $RELAYER == "hermes" ]; then

    echo "> Installing Hermes"
    sudo apt-get install protobuf-compiler
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -y
    cargo install ibc-relayer-cli --bin hermes --locked --version ${HERMES_VERSION:1}
    hermes version
    mkdir -p ~/.hermes

    # echo "Downloading Hermes..."
    # wget -q https://github.com/informalsystems/hermes/releases/download/$HERMES_VERSION/hermes-$HERMES_VERSION-x86_64-unknown-linux-gnu.tar.gz -O hermes-$HERMES_VERSION.tar.gz
    # tar -xzvf hermes-$HERMES_VERSION.tar.gz
    # mkdir -p ~/.hermes
    # hermes version
    # cp hermes ~/.hermes/hermes
    # export PATH="$PATH:~/.hermes"

    echo "Setting up Hermes config..."
    cp templates/hermes-config.toml ~/.hermes/config.toml

    echo "Adding relayer keys..."
    echo $MNEMONIC_RELAYER > mnemonic.txt
    hermes keys add --chain $CHAIN_ID --mnemonic-file mnemonic.txt
    hermes keys add --chain v400-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v640-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v640-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v701-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v701-two --mnemonic-file mnemonic.txt
    hermes keys add --chain stride-test --mnemonic-file mnemonic.txt
    hermes keys add --chain neutron-test --mnemonic-file mnemonic.txt
    hermes keys add --chain pfm1 --mnemonic-file mnemonic.txt
    hermes keys add --chain pfm2 --mnemonic-file mnemonic.txt
    hermes keys add --chain pfm3 --mnemonic-file mnemonic.txt
    hermes keys add --chain two --mnemonic-file mnemonic.txt

elif [ $RELAYER == "rly" ]; then

    echo "Downloading rly..."
    RLY_DOWNLOAD_URL="https://github.com/cosmos/relayer/releases/download/v${RLY_VERSION}/Cosmos.Relayer_${RLY_VERSION}_linux_amd64.tar.gz"
    wget -q $RLY_DOWNLOAD_URL -O rly-v$RLY_VERSION.tar.gz
    tar -xzvf rly-v$RLY_VERSION.tar.gz
    mkdir -p ~/.relayer
    mv Cosmos*/rly ~/.relayer/rly

    echo "Setting up rly config..."
    rly config init

    echo "Adding chains to config..."
    # provider
    rly chains add --file templates/testnet.json

    # v400-one
    jq '.value."chain-id" = "v400-one"' templates/testnet.json > v400-1.json
    jq '.value."rpc-addr" = "http://localhost:40121"' v400-1.json > v400-2.json
    jq '.value."gas-prices" = "0.005ucon"' v400-2.json > v400-one.json
    cat v400-one.json
    rly chains add --file v400-one.json

    # v400-two
    jq '.value."chain-id" = "v400-two"' templates/testnet.json > v400-1.json
    jq '.value."rpc-addr" = "http://localhost:40221"' v400-1.json > v400-2.json
    jq '.value."gas-prices" = "0.005ucon"' v400-2.json > v400-two.json
    cat v400-two.json
    rly chains add --file v400-two.json

    # Stride
    jq '.value."chain-id" = "stride-test"' templates/testnet.json > stride-1.json
    jq '.value."rpc-addr" = "http://localhost:32321"' stride-1.json > stride-2.json
    jq '.value."account-prefix" = "stride"' stride-2.json > stride-3.json
    jq '.value."gas-prices" = "0.0025ustrd"' stride-3.json > stride-test.json
    cat stride-test.json
    rly chains add --file stride-test.json

    # Neutron
    jq '.value."chain-id" = "neutron-test"' templates/testnet.json > neutron-1.json
    jq '.value."rpc-addr" = "http://localhost:31321"' neutron-1.json > neutron-2.json
    jq '.value."account-prefix" = "neutron"' neutron-2.json > neutron-3.json
    jq '.value."gas-prices" = "0.0025untrn"' neutron-3.json > neutron-test.json
    cat neutron-test.json
    rly chains add --file neutron-test.json

    # pfm-1
    jq '.value."chain-id" = "pfm1"' templates/testnet.json > p.json
    jq '.value."rpc-addr" = "http://localhost:27011"' p.json > pf.json
    jq '.value."gas-prices" = "0.005uatom"' pf.json > pfm1.json
    rly chains add --file pfm1.json

    # pfm-2
    jq '.value."chain-id" = "pfm2"' templates/testnet.json > p.json
    jq '.value."rpc-addr" = "http://localhost:27012"' p.json > pf.json
    jq '.value."gas-prices" = "0.005uatom"' pf.json > pfm2.json
    rly chains add --file pfm2.json

    # pfm-3
    jq '.value."chain-id" = "pfm3"' templates/testnet.json > p.json
    jq '.value."rpc-addr" = "http://localhost:27013"' p.json > pf.json
    jq '.value."gas-prices" = "0.005uatom"' pf.json > pfm3.json
    rly chains add --file pfm3.json

    cat ~/.relayer/config/config.yaml

    echo "Adding relayer keys..."
    rly keys restore $CHAIN_ID default "$MNEMONIC_RELAYER"
    rly keys restore v400-one default "$MNEMONIC_RELAYER"
    rly keys restore v400-two default "$MNEMONIC_RELAYER"
    rly keys restore stride-test default "$MNEMONIC_RELAYER"
    rly keys restore neutron-test default "$MNEMONIC_RELAYER"
    rly keys restore pfm1 default "$MNEMONIC_RELAYER"
    rly keys restore pfm2 default "$MNEMONIC_RELAYER"
    rly keys restore pfm3 default "$MNEMONIC_RELAYER"
fi

echo "Creating service..."
sudo touch /etc/systemd/system/$RELAYER.service
echo "[Unit]"                               | sudo tee /etc/systemd/system/$RELAYER.service
echo "Description=Relayer service"          | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$RELAYER.service -a
echo ""                                     | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$RELAYER.service -a

if [ $RELAYER == "hermes" ]; then
    # echo "ExecStart=$HOME/.hermes/$RELAYER start"    | sudo tee /etc/systemd/system/$RELAYER.service -a
    echo "ExecStart=$HOME/.cargo/bin/$RELAYER start"    | sudo tee /etc/systemd/system/$RELAYER.service -a
elif [ $RELAYER == "rly" ]; then
    echo "ExecStart=$HOME/.relayer/$RELAYER start"   | sudo tee /etc/systemd/system/$RELAYER.service -a
fi
echo "Restart=no"                           | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$RELAYER.service -a
echo ""                                     | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$RELAYER.service -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$RELAYER.service -a

echo "Creating evidence service..."
sudo touch /etc/systemd/system/hermes-evidence.service
echo "[Unit]"                               | sudo tee /etc/systemd/system/hermes-evidence.service
echo "Description=Hermes evidence service"          | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo ""                                     | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "[Service]"                            | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/hermes-evidence.service -a

# echo "ExecStart=$HOME/.hermes/hermes evidence"    | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "ExecStart=$HOME/.cargo/bin/hermes evidence"    | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo ""                                     | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "[Install]"                            | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/hermes-evidence.service -a

sudo systemctl daemon-reload
sudo systemctl enable $RELAYER
sudo systemctl enable hermes-evidence
sleep 10
journalctl -u $RELAYER | tail -n 100