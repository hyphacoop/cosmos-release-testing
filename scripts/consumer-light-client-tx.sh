#!/bin/bash
# Test equivocation for light client attack
LC_CONSUMER_HOME_1=/home/runner/.lc1
LC_CONSUMER_HOME_2=/home/runner/.lc2
LC_CONSUMER_SERVICE_1=lc_consumer_1.service
LC_CONSUMER_SERVICE_2=lc_consumer_2.service
LC_CON_API_PORT_1=61102
LC_CON_API_PORT_2=61202
LC_CON_GRPC_PORT_1=60112
LC_CON_GRPC_PORT_2=60212
LC_CON_RPC_PORT_1=60122
LC_CON_RPC_PORT_2=60222
LC_CON_P2P_PORT_1=60132
LC_CON_P2P_PORT_2=61232
LC_CON_PPROF_PORT_1=60142
LC_CON_PPROF_PORT_2=60242

# Validators 1 and 2 will copy the chain

echo "> 0. Get trusted height using provider consensus state."
# ibc_client=$($CHAIN_BINARY q provider list-consumer-chains -o json --home $HOME_1 | jq '.')
client_id=$($CHAIN_BINARY q provider list-consumer-chains -o json --home $HOME_1 | jq -r --arg chain "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id==$chain).client_id')
echo "> Client ID: $client_id"
echo "> Hermes:"
hermes --json query client consensus --chain $CHAIN_ID --client $client_id | tail -n 1 | jq '.'
echo "> Gaia:"
$CHAIN_BINARY q ibc client consensus-state-heights $client_id --home $HOME_1 -o json | jq -r '.'

TRUSTED_HEIGHT=$($CHAIN_BINARY q ibc client consensus-state-heights $client_id --home $HOME_1 -o json | jq -r '.consensus_state_heights[-1].revision_height')
echo "> Trusted height: $TRUSTED_HEIGHT"

echo "> 1. Copy validator home folders."
cp -r $CONSUMER_HOME_1 $LC_CONSUMER_HOME_1
cp -r $CONSUMER_HOME_2 $LC_CONSUMER_HOME_2

echo "LC1 genesis file:"
jq '.' $LC_CONSUMER_HOME_1/config/genesis.json

echo "> 2. Clear persistent peers."
CON1_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $LC_CONSUMER_HOME_1)
CON2_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $LC_CONSUMER_HOME_2)
CON1_PEER="$CON1_NODE_ID@127.0.0.1:$LC_CON_P2P_PORT_1"
CON2_PEER="$CON2_NODE_ID@127.0.0.1:$LC_CON_P2P_PORT_2"
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.persistent_peers "$CON2_PEER"
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml p2p.persistent_peers "$CON1_PEER"

echo "> 3. Update ports..."
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml api.address "tcp://0.0.0.0:$LC_CON_API_PORT_1"
toml set --toml-path $LC_CONSUMER_HOME_2/config/app.toml api.address "tcp://0.0.0.0:$LC_CON_API_PORT_2"
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml grpc.address "0.0.0.0:$LC_CON_GRPC_PORT_1"
toml set --toml-path $LC_CONSUMER_HOME_2/config/app.toml grpc.address "0.0.0.0:$LC_CON_GRPC_PORT_2"
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml rpc.laddr "tcp://0.0.0.0:$LC_CON_RPC_PORT_1"
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml rpc.laddr "tcp://0.0.0.0:$LC_CON_RPC_PORT_2"
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml rpc.pprof_laddr "127.0.0.1:$LC_CON_PPROF_PORT_1"
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml rpc.pprof_laddr "127.0.0.1:$LC_CON_PPROF_PORT_2"
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.laddr "tcp://0.0.0.0:$LC_CON_P2P_PORT_1"
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml p2p.laddr "tcp://0.0.0.0:$LC_CON_P2P_PORT_2"

echo "> 4. Wipe the address book..."
echo "{}" > $LC_CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $LC_CONSUMER_HOME_2/config/addrbook.json

echo "> 5. Set up new services..."

sudo touch /etc/systemd/system/$LC_CONSUMER_SERVICE_1
echo "[Unit]"                               | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1
echo "Description=Consumer service"         | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $LC_CONSUMER_HOME_1" | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a

sudo touch /etc/systemd/system/$LC_CONSUMER_SERVICE_2
echo "[Unit]"                               | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2
echo "Description=Consumer service"         | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $LC_CONSUMER_HOME_2" | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a

sudo systemctl enable $LC_CONSUMER_SERVICE_1 --now
sudo systemctl enable $LC_CONSUMER_SERVICE_2 --now
sleep 30

journalctl -u $LC_CONSUMER_SERVICE_1

echo "> Get current height header from main consumer"
OG_HEIGHT=$($CONSUMER_CHAIN_BINARY status --home $CONSUMER_HOME_1 | jq -r '.sync_info.latest_block_height')
echo "Height: $OG_HEIGHT"
sleep 5
echo "> Get IBC header from main consumer:"
OG_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $OG_HEIGHT --home $CONSUMER_HOME_1 -o json)
echo "$OG_HEADER"
echo "> Get IBC header from second consumer:"
LC_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $OG_HEIGHT --home $LC_CONSUMER_HOME_1 -o json)
echo "$LC_HEADER"

## Get IBC header at trusted height +1 since the trusted validators hash
## corresponds to the consensus state "NextValidatorHash" of the consumer client
echo "> IBC header at trusted height + 1 from main consumer:"
TRUSTED_HEADER=$($CONSUMER_CHAIN_BINARY q ibc client header --height $(($TRUSTED_HEIGHT +1)) --home $CONSUMER_HOME_1 -o json
echo "$TRUSTED_HEADER"

## Create a consumer misbehaviour struct by joining the conflicting headers
## updated with trusted header info

echo "> Fill trusted valset and height"
TRUSTED_VALS=$(echo $TRUSTED_HEADER | jq -r '.validator_set')
OG_HEADERHEADER=$(echo $OG_HEADER | jq --argjson vals "$TRUSTED_VALS" '.trusted_validators = $vals')
LC_HEADER=$(echo $LC_BAD_HEADER | jq --argjson vals "$TRUSTED_VALS" '.trusted_validators = $vals')

OG_HEADER=$(echo $HEADER | jq --arg height $TRUSTED_HEIGHT '.trusted_height.revision_height = $height')
LC_HEADER=$(echo $BAD_HEADER | jq --arg height $TRUSTED_HEIGHT '.trusted_height.revision_height = $height')

tee lc_misbehaviour.json<<EOF
{
    "client_id": "$client_id",
    "header_1": $OG_HEADER,
    "header_2": $LC_HEADER
}
EOF

jq '.' misbehaviour.json
exit 0


echo "Hermes:"
journalctl -u hermes | tail -n 100
echo "consumer 1:"
journalctl -u $CONSUMER_SERVICE_1 | tail -n 20
echo "consumer 1 lc:"
journalctl -u $LC_CONSUMER_SERVICE_1 | tail -n 20
echo "validator 1:"
journalctl -u $PROVIDER_SERVICE_1 | tail -n 10

$CHAIN_BINARY q ibc client status 07-tendermint-0 --home $HOME_1
$CHAIN_BINARY q ibc client state 07-tendermint-0 -o json --home $HOME_1 | jq '.'
$CHAIN_BINARY q ibc client state 07-tendermint-0 -o json --home $HOME_1 | jq -r '.client_state.frozen_height'

$CHAIN_BINARY q slashing signing-infos --home $HOME_1
