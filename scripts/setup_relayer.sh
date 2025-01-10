#!/bin/bash
# Set up a relayer

if [ $RELAYER == "hermes" ]; then

    echo "Downloading Hermes..."
    wget -q https://github.com/informalsystems/hermes/releases/download/$HERMES_VERSION/hermes-$HERMES_VERSION-x86_64-unknown-linux-gnu.tar.gz -O hermes-$HERMES_VERSION.tar.gz
    tar -xzvf hermes-$HERMES_VERSION.tar.gz
    mkdir -p ~/.hermes
    cp hermes ~/.hermes/hermes
    export PATH="$PATH:~/.hermes"

    echo "Setting up Hermes config..."
    cp templates/hermes-config.toml ~/.hermes/config.toml

    echo "Adding relayer keys..."
    echo $MNEMONIC_RELAYER > mnemonic.txt
    hermes keys add --chain $CHAIN_ID --mnemonic-file mnemonic.txt
    hermes keys add --chain v310-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v310-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v320-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v320-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v330-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v330-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v400-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v450-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v450-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v520-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v630-one --mnemonic-file mnemonic.txt
    hermes keys add --chain v630-two --mnemonic-file mnemonic.txt
    hermes keys add --chain v640-one --mnemonic-file mnemonic.txt
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

    # two
    # jq '.value."chain-id" = "two-v200"' tests/v15_upgrade/testnet.json > two-1.json
    # jq '.value."rpc-addr" = "http://localhost:27201"' two-1.json > two-2.json
    # jq '.value."gas-prices" = "0.005ucon"' two-2.json > two-v200.json
    # cat two-v200.json
    # rly chains add --file two-v200.json

    # v310-one
    jq '.value."chain-id" = "v310-one"' templates/testnet.json > v310-1.json
    jq '.value."rpc-addr" = "http://localhost:31121"' v310-1.json > v310-2.json
    jq '.value."gas-prices" = "0.005ucon"' v310-2.json > v310-one.json
    cat v310-one.json
    rly chains add --file v310-one.json

    # v310-two
    jq '.value."chain-id" = "v310-two"' templates/testnet.json > v310-1.json
    jq '.value."rpc-addr" = "http://localhost:31221"' v310-1.json > v310-2.json
    jq '.value."gas-prices" = "0.005ucon"' v310-2.json > v310-two.json
    cat v310-two.json
    rly chains add --file v310-two.json

    # v320-one
    jq '.value."chain-id" = "v320-one"' templates/testnet.json > v320-1.json
    jq '.value."rpc-addr" = "http://localhost:32121"' v320-1.json > v320-2.json
    jq '.value."gas-prices" = "0.005ucon"' v320-2.json > v320-one.json
    cat v320-one.json
    rly chains add --file v320-one.json

    # v320-two
    jq '.value."chain-id" = "v320-two"' templates/testnet.json > v320-1.json
    jq '.value."rpc-addr" = "http://localhost:32221"' v320-1.json > v320-2.json
    jq '.value."gas-prices" = "0.005ucon"' v320-2.json > v320-two.json
    cat v320-two.json
    rly chains add --file v320-two.json

    # v330-one
    jq '.value."chain-id" = "v330-one"' templates/testnet.json > v330-1.json
    jq '.value."rpc-addr" = "http://localhost:33121"' v330-1.json > v330-2.json
    jq '.value."gas-prices" = "0.005ucon"' v330-2.json > v330-one.json
    cat v330-one.json
    rly chains add --file v330-one.json

    # v330-two
    jq '.value."chain-id" = "v330-two"' templates/testnet.json > v330-1.json
    jq '.value."rpc-addr" = "http://localhost:33221"' v330-1.json > v330-2.json
    jq '.value."gas-prices" = "0.005ucon"' v330-2.json > v330-two.json
    cat v330-two.json
    rly chains add --file v330-two.json

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
    rly keys restore v310-one default "$MNEMONIC_RELAYER"
    rly keys restore v310-two default "$MNEMONIC_RELAYER"
    rly keys restore v320-one default "$MNEMONIC_RELAYER"
    rly keys restore v320-two default "$MNEMONIC_RELAYER"
    rly keys restore v330-one default "$MNEMONIC_RELAYER"
    rly keys restore v330-two default "$MNEMONIC_RELAYER"
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
    echo "ExecStart=$HOME/.hermes/$RELAYER start"    | sudo tee /etc/systemd/system/$RELAYER.service -a
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

echo "ExecStart=$HOME/.hermes/hermes evidence"    | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo ""                                     | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "[Install]"                            | sudo tee /etc/systemd/system/hermes-evidence.service -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/hermes-evidence.service -a

sudo systemctl daemon-reload
sudo systemctl enable $RELAYER
sudo systemctl enable hermes-evidence
