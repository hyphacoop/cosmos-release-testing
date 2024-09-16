#!/bin/bash
# Test equivocation for light client attack
LC_CONSUMER_HOME_1=/home/runner/.lc1
LC_CONSUMER_HOME_2=/home/runner/.lc2
LC_CONSUMER_SERVICE_1=lc_consumer_1.service
LC_CONSUMER_SERVICE_2=lc_consumer_2.service
LC_CON_API_PORT_1=60102
LC_CON_API_PORT_2=61202
LC_CON_GRPC_PORT_1=60112
LC_CON_GRPC_PORT_2=60212
LC_CON_RPC_PORT_1=60122
LC_CON_RPC_PORT_2=60222
LC_CON_P2P_PORT_1=60132
LC_CON_P2P_PORT_2=61232
LC_CON_PPROF_PORT_1=60142
LC_CON_PPROF_PORT_2=60242

echo "Setting up consumer nodes..."
$CONSUMER_CHAIN_BINARY config chain-id $CONSUMER_CHAIN_ID --home $LC_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config keyring-backend test --home $LC_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY config node tcp://localhost:$LC_CON_RPC_PORT_1 --home $LC_CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY init lc1 --chain-id $CONSUMER_CHAIN_ID --home $LC_CONSUMER_HOME_1

$CONSUMER_CHAIN_BINARY config chain-id $CONSUMER_CHAIN_ID --home $LC_CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config keyring-backend test --home $LC_CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY config node tcp://localhost:$LC_CON_RPC_PORT_2 --home $LC_CONSUMER_HOME_2
$CONSUMER_CHAIN_BINARY init lc2 --chain-id $CONSUMER_CHAIN_ID --home $LC_CONSUMER_HOME_2

# Validators 1 and 2 will copy the chain

echo "> 0. Get trusted height."
ibc_client=$($CHAIN_BINARY q provider list-consumer-chains -o json | jq '.')

TRUSTED_HEIGHT=$(hermes --json query client consensus --chain $CHAIN_ID --client 07-tendermint-0 | tail -n 1 | jq '.result[2].revision_height')
echo "> Trusted height: $TRUSTED_HEIGHT"

echo "> 1. Copy validator home folders."
cp -r $CONSUMER_HOME_1 $LC_CONSUMER_HOME_1
cp -r $CONSUMER_HOME_2 $LC_CONSUMER_HOME_2

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
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $CONSUMER_HOME_2" | sudo tee /etc/systemd/system/$CONSUMER_SERVICE_2 -a
echo "Restart=no"                           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a

sudo systemctl enable $LC_CONSUMER_SERVICE_1 --now
sudo systemctl enable $LC_CONSUMER_SERVICE_2 --now
sleep 30

journalctl -u $LC_CONSUMER_SERVICE_1

echo "> 6. Update the light client of the consumer chain on the provider chain."
hermes --config ~/.hermes/config-lc.toml update client --client 07-tendermint-0 --host-chain $CHAIN_ID --trusted-height $TRUSTED_HEIGHT

exit 0

echo "Getting patched genesis file..."
cp $CONSUMER_HOME_1/config/genesis.json $LC_CONSUMER_HOME_1/config/genesis.json

echo "Patching config files..."
# app.toml
# minimum_gas_prices
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"0$CONSUMER_DENOM\"^" $LC_CONSUMER_HOME_1/config/app.toml
# Enable API
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml api.enable true
# Set different ports for api
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml api.address "tcp://0.0.0.0:$LC_CON_API_PORT_1"
# Set different ports for grpc
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml grpc.address "0.0.0.0:$LC_CON_GRPC_PORT_1"
# Turn off grpc web
toml set --toml-path $LC_CONSUMER_HOME_1/config/app.toml grpc-web.enable false
# config.toml
# Set different ports for rpc
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml rpc.laddr "tcp://0.0.0.0:$LC_CON_RPC_PORT_1"
# Set different ports for rpc pprof
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml rpc.pprof_laddr "localhost:$LC_CON_PPROF_PORT_1"
# Set different ports for p2p
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.laddr "tcp://0.0.0.0:$LC_CON_P2P_PORT_1"
echo "Set no strict address book rules..."
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.addr_book_strict false
# Allow duplicate IPs in p2p
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.allow_duplicate_ip true
echo "Setting persistent peer..."
CON2_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_2)
CON2_PEER="$CON2_NODE_ID@localhost:$CON2_P2P_PORT"
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml p2p.persistent_peers "$CON2_PEER"
echo "Setting a short commit timeout..."
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
# Set fast_sync to false - or block_sync for ICS v3
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml fast_sync false
toml set --toml-path $LC_CONSUMER_HOME_1/config/config.toml block_sync false

echo "Setting up services..."

sudo touch /etc/systemd/system/$LC_CONSUMER_SERVICE_1
echo "[Unit]"                               | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1
echo "Description=Consumer service"       | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "User=$USER"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $LC_CONSUMER_HOME_1" | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "Restart=no"                       | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_1 -a

sudo touch /etc/systemd/system/$LC_CONSUMER_SERVICE_2
echo "[Unit]"                               | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2
echo "Description=Consumer service"       | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "User=$USER"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "ExecStart=$HOME/go/bin/$CONSUMER_CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $LC_CONSUMER_HOME_2" | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "Restart=no"                       | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo ""                                     | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$LC_CONSUMER_SERVICE_2 -a

echo "Starting consumer service..."
sudo systemctl enable $LC_CONSUMER_SERVICE_1 --now

sleep 30
# journalctl -u $LC_CONSUMER_SERVICE_1

echo "> Submitting opt-in transaction."
key=$($CONSUMER_CHAIN_BINARY tendermint show-validator --home $LC_CONSUMER_HOME_1)
echo "Consumer key: $key"
echo "Consumer ID: $CONSUMER_ID"
command="$CHAIN_BINARY tx provider opt-in $CONSUMER_ID $key --from $malval_det --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM --home $LC_PROVIDER_HOME -y"
echo $command
$command

sleep 30
$CHAIN_BINARY q provider validator-consumer-key $CONSUMER_ID $($CHAIN_BINARY tendermint show-address --home $LC_PROVIDER_HOME) --home $HOME_1

echo "Check validator is in the consumer chain..."
total_after=$(curl -s http://localhost:$CON1_RPC_PORT/validators | jq -r '.result.total')
total=$(( $total_after - $total_before ))

if [ $total == 1 ]; then
  echo "Validator created!"
else
  echo "Validator not created."
  exit 1
fi

val_bytes=$($CHAIN_BINARY keys parse $malval_det --output json | jq -r '.bytes')
LC_valoper=$($CHAIN_BINARY keys parse $val_bytes --output json | jq -r '.formats[2]')
echo "Validator address: $LC_valoper"

echo "> Consumer block from double-signing validator node 1:"
$CONSUMER_CHAIN_BINARY q block --home $LC_CONSUMER_HOME_1 | jq '.'


echo "> Unbonding from validator."
$CHAIN_BINARY tx staking unbond $LC_valoper $UNBOND_AMOUNT$DENOM --from $malval_det --home $LC_PROVIDER_HOME --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Redelegating from validator."
$CHAIN_BINARY tx staking redelegate $LC_valoper $VALOPER_3 $REDELEGATE_AMOUNT$DENOM --from $malval_det --home $LC_PROVIDER_HOME --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y
sleep $(($COMMIT_TIMEOUT*2))

start_tokens=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$LC_valoper" '.validators[] | select(.operator_address==$oper).tokens')
start_unbonding=$($CHAIN_BINARY q staking unbonding-delegations-from $LC_valoper --home $HOME_1 -o json | jq -r '.unbonding_responses[0].entries[0].balance')
start_redelegation_dest=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$VALOPER_3" '.validators[] | select(.operator_address==$oper).tokens')

echo "Attempting to double sign..."

# Stop whale
echo "Stopping whale validator..."
sudo systemctl stop $CONSUMER_SERVICE_1
sudo systemctl stop $CONSUMER_SERVICE_2
sudo systemctl stop $CONSUMER_SERVICE_3
sleep 5

# Stop validator
sudo systemctl stop $LC_CONSUMER_SERVICE_1
sleep 3
# Duplicate home folder
echo "Duplicating home folder..."
cp -r $LC_CONSUMER_HOME_1/ $LC_CONSUMER_HOME_2/

CON3_NODE_ID=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home $CONSUMER_HOME_3)
CON3_PEER="$CON3_NODE_ID@localhost:$CON3_P2P_PORT"
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml p2p.persistent_peers "$CON3_PEER"

# Update ports
toml set --toml-path $LC_CONSUMER_HOME_2/config/app.toml api.address "tcp://0.0.0.0:$LC_CON_API_PORT_2"
# Set different ports for grpc
toml set --toml-path $LC_CONSUMER_HOME_2/config/app.toml grpc.address "0.0.0.0:$LC_CON_GRPC_PORT_2"
# config.toml
# Set different ports for rpc
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml rpc.laddr "tcp://0.0.0.0:$LC_CON_RPC_PORT_2"
# Set different ports for rpc pprof
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml rpc.pprof_laddr "localhost:$LC_CON_PPROF_PORT_2"
# Set different ports for p2p
toml set --toml-path $LC_CONSUMER_HOME_2/config/config.toml p2p.laddr "tcp://0.0.0.0:$LC_CON_P2P_PORT_2"

# Wipe the state and address books
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $LC_CONSUMER_HOME_1/data/priv_validator_state.json
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $LC_CONSUMER_HOME_2/data/priv_validator_state.json
echo "{}" > $LC_CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $LC_CONSUMER_HOME_1/config/addrbook.json

# Start duplicate node
echo "> Starting second node."
sudo systemctl enable $LC_CONSUMER_SERVICE_2 --now
# sleep 10

# Start original node
echo "> Starting first node."
sudo systemctl start $LC_CONSUMER_SERVICE_1
sleep 10

echo "{}" > $CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_3/config/addrbook.json

# Restart whale
echo "> Restarting whale validator."
sudo systemctl start $CONSUMER_SERVICE_2
sudo systemctl start $CONSUMER_SERVICE_3
sleep 60
sudo systemctl start $CONSUMER_SERVICE_1
echo "> Restarting Hermes."
sudo systemctl restart $RELAYER
sleep 60

# Restart nodes again
echo "Restarting nodes again..."
sudo systemctl stop $CONSUMER_SERVICE_1
sudo systemctl stop $CONSUMER_SERVICE_2
sudo systemctl stop $CONSUMER_SERVICE_3
sudo systemctl stop $LC_CONSUMER_SERVICE_1
sudo systemctl stop $LC_CONSUMER_SERVICE_2
sleep 2
# Wipe the state and address books
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $LC_CONSUMER_HOME_1/data/priv_validator_state.json
echo '{"height": "0","round": 0,"step": 0,"signature":"","signbytes":""}' > $LC_CONSUMER_HOME_2/data/priv_validator_state.json
echo "{}" > $LC_CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $LC_CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_1/config/addrbook.json
echo "{}" > $CONSUMER_HOME_2/config/addrbook.json
echo "{}" > $CONSUMER_HOME_3/config/addrbook.json
sudo systemctl start $CONSUMER_SERVICE_2
sudo systemctl start $CONSUMER_SERVICE_3
sudo systemctl start $LC_CONSUMER_SERVICE_1
sudo systemctl start $LC_CONSUMER_SERVICE_2
sleep 60
sudo systemctl start $CONSUMER_SERVICE_1
echo "> Restarting Hermes."
sudo systemctl restart $RELAYER
sleep 60

echo "> Node 1:"
journalctl -u $LC_CONSUMER_SERVICE_1
echo "> Node 2:"
journalctl -u $LC_CONSUMER_SERVICE_2

echo "> Consumer chain evidence:"
$CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq '.'

consensus_address=$($CONSUMER_CHAIN_BINARY tendermint show-address --home $LC_CONSUMER_HOME_1)
validator_check=$($CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq '.' | grep $consensus_address)
echo $validator_check
if [ -z "$validator_check" ]; then
  echo "No equivocation evidence found."
  exit 1
else
  echo "Equivocation evidence found!"
fi

echo "> Collecting infraction height."
height=$($CONSUMER_CHAIN_BINARY q evidence --home $CONSUMER_HOME_1 -o json | jq -r '.evidence[0].height')
echo "> Evidence height: $height"

echo "> Collecting evidence around the infraction height in consumer chain."
height_1=$(($height-1))
evidence_block=$(($height+1))
evidence_block_1=$(($height+2))
echo "> Consumer evidence at height $height_1:"
$CONSUMER_CHAIN_BINARY q block $height_1 --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $height:"
$CONSUMER_CHAIN_BINARY q block $height --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block:"
$CONSUMER_CHAIN_BINARY q block $evidence_block --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block_1:"
$CONSUMER_CHAIN_BINARY q block $evidence_block_1 --home $CONSUMER_HOME_1 | jq '.'
echo "> Consumer evidence at height $evidence_block_1 (gaiad):"
$CHAIN_BINARY q block --type=height $evidence_block_1 --home $CONSUMER_HOME_1
$CONSUMER_CHAIN_BINARY q block $evidence_block_1 --home $CONSUMER_HOME_1 | jq '.block.evidence.evidence[0].value' > evidence.json
echo "> Evidence JSON:"
jq '.' evidence.json

echo "***** EVIDENCE JSON MODIFICATION BEGINS *****"

echo "> Cast vote a height as integer."
jq '.vote_a.height |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast vote b height as integer."
jq '.vote_b.height |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote a block id hash."
hash=$(jq -r '.vote_a.block_id.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_a.block_id.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote a block id part hash."
hash=$(jq -r '.vote_a.block_id.parts.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_a.block_id.parts.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote b block id hash."
hash=$(jq -r '.vote_b.block_id.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_b.block_id.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote b block id part hash."
hash=$(jq -r '.vote_b.block_id.parts.hash' evidence.json | xxd -r -p | base64)
echo "Hash: >$hash<"
jq --arg HASH "$hash" '.vote_b.block_id.parts.hash |= $HASH' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename vote_a parts key."
jq '.vote_a.block_id.parts as $p | .vote_a.block_id.part_set_header = $p | del(.vote_a.block_id.parts)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename vote_b parts key."
jq '.vote_b.block_id.parts as $p | .vote_b.block_id.part_set_header = $p | del(.vote_b.block_id.parts)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json
jq '.' evidence.json

echo "> Base64 encode vote_a val address."
addr=$(jq -r '.vote_a.validator_address' evidence.json | xxd -r -p | base64)
echo "Base64-encoded: $addr"
jq --arg ADDR "$addr" '.vote_a.validator_address |= $ADDR' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Base64 encode vote_b val address."
addr=$(jq -r '.vote_b.validator_address' evidence.json | xxd -r -p | base64)
echo "Base64-encoded: $addr"
jq --arg ADDR "$addr" '.vote_b.validator_address |= $ADDR' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename total voting power."
jq '.TotalVotingPower as $p | .total_voting_power = $p | del(.TotalVotingPower)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename validator power key."
jq '.ValidatorPower as $p | .validator_power = $p | del(.ValidatorPower)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Rename timestamp key."
jq '.Timestamp as $p | .timestamp = $p | del(.Timestamp)' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast total voting power as integer."
jq '.total_voting_power |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

echo "> Cast validator power as integer."
jq '.validator_power |= tonumber' evidence.json > evidence-mod.json
mv evidence-mod.json evidence.json

jq '.' evidence.json

echo "***** EVIDENCE JSON MODIFICATION ENDS *****"

echo "> IBC header signatures at height $(($height-2))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height-2)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height-1))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height-1)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height+1))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height+1)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'
echo "> IBC header signatures at height $(($height+2))"
$CONSUMER_CHAIN_BINARY q ibc client header --height $(($height+2)) --home $CONSUMER_HOME_1 -o json | jq '.signed_header.commit.signatures | length'


echo "> Collecting IBC header at infraction height in consumer chain."
$CONSUMER_CHAIN_BINARY q ibc client header --height $height --home $CONSUMER_HOME_1 -o json | jq '.' > ibc-header.json
echo "> IBC header JSON:"
jq '.' ibc-header.json

echo "***** IBC HEADER JSON MODIFICATION BEGINS *****"

echo "> Cast header height to integer."
jq '.signed_header.header.height |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast commit height to integer."
jq '.signed_header.commit.height |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Replace BLOCK_ID_FLAG_COMMIT with 2."
sed "s%\"BLOCK_ID_FLAG_COMMIT\"%2%g" ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Replace BLOCK_ID_FLAG_NIL with 3."
sed "s%\"BLOCK_ID_FLAG_NIL\"%3%g" ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast validators' voting power to integer."
jq '.validator_set.validators[].voting_power |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast validators' proposer priority to integer."
jq '.validator_set.validators[].proposer_priority |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast proposer's voting power to integer."
jq '.validator_set.proposer.voting_power |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Cast proposer's proposer priority to integer."
jq '.validator_set.proposer.proposer_priority |= tonumber' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Remove total_voting_power."
jq 'del(.validator_set.total_voting_power)' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

echo "> Remove revision_number."
jq 'del(.trusted_height.revision_number)' ibc-header.json > header-mod.json
mv header-mod.json ibc-header.json

jq '.' ibc-header.json

echo "***** IBC HEADER JSON MODIFICATION ENDS *****"


echo "> Submitting evidence."
txhash=$($CHAIN_BINARY tx provider submit-consumer-double-voting $CONSUMER_ID evidence.json ibc-header.json \
    --from $WALLET_1  --home $HOME_1 --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y -o json | jq -r '.txhash')
sleep $(($COMMIT_TIMEOUT*2))
echo "> Evidence submission tx:"
$CHAIN_BINARY q tx $txhash --home $HOME_1 -o json | jq '.'

# sudo systemctl enable hermes-evidence --now

# echo "Wait for evidence to reach the provider chain..."
# sleep 60

# journalctl -u hermes-evidence
echo "> Wait for validator to be removed from validator set."
sleep $(($COMMIT_TIMEOUT*2))
echo "> Signing infos:"
$CHAIN_BINARY q slashing signing-infos --home $HOME_1 -o json | jq '.'
echo "> Signing info:"
$CHAIN_BINARY q slashing signing-info $($CHAIN_BINARY tendermint show-validator --home $LC_PROVIDER_HOME) --home $HOME_1 -o json | jq '.'
echo "> Validators:"
$CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq '.'

status=$($CHAIN_BINARY q slashing signing-info $($CHAIN_BINARY tendermint show-validator --home $LC_PROVIDER_HOME) --home $HOME_1 -o json | jq '.val_signing_info.tombstoned')
echo "Status: $status"
if [ $status == "true" ]; then
  echo "Success: validator has been tombstoned!"
else
  echo "Failure: validator was not tombstoned."
  exit 1
fi

echo "Slashing checks:"
end_tokens=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$LC_valoper" '.validators[] | select(.operator_address==$oper).tokens')
end_unbonding=$($CHAIN_BINARY q staking unbonding-delegations-from $LC_valoper --home $HOME_1 -o json | jq -r '.unbonding_responses[0].entries[0].balance')
end_redelegation_dest=$($CHAIN_BINARY q staking validators --home $HOME_1 -o json | jq -r --arg oper "$VALOPER_3" '.validators[] | select(.operator_address==$oper).tokens')

echo "Validator tokens: $start_tokens -> $end_tokens"
echo "Unbonding delegations: $start_unbonding -> $end_unbonding"
echo "Redelegation recipient: $start_redelegation_dest -> $end_redelegation_dest"

expected_slashed_tokens=$(echo "$SLASH_FACTOR * $start_tokens" | bc -l)
expected_slashed_unbonding=$(echo "$SLASH_FACTOR * $start_unbonding" | bc -l)
expected_slashed_redelegation=$(echo "$SLASH_FACTOR * $REDELEGATE_AMOUNT" | bc -l)
expected_slashed_total=$(echo "$SLASH_FACTOR * ($start_tokens + $start_unbonding + $REDELEGATE_AMOUNT)" | bc -l)

bonded_tokens_slashed=$(echo "$start_tokens - $end_tokens" | bc)
unbonding_slashed=$(echo "$start_unbonding - $end_unbonding" | bc)
redelegation_dest_slashed=$(echo "$start_redelegation_dest - $end_redelegation_dest" | bc)
total_slashed=$(echo "$bonded_tokens_slashed + $unbonding_slashed + $redelegation_dest_slashed" | bc -l)
echo "Tokens slashed: $bonded_tokens_slashed, expected: $expected_slashed_tokens"
echo "Unbonding delegations slashed: $unbonding_slashed, expected: $expected_slashed_unbonding"
echo "Redelegations slashed: $redelegation_dest_slashed, expected: $expected_slashed_redelegation"
echo "Total slashed: $total_slashed, expected: $expected_slashed_total"

if [[ $total_slashed -ne ${expected_slashed_total%.*} ]]; then
  echo "Total slashed tokens does not match expected value."
  exit 1
else
  echo "Total slashed tokens: pass"
fi

if [[ $bonded_tokens_slashed -ne ${expected_slashed_tokens%.*} ]]; then
  echo "Slashed bonded tokens does not match expected value."
  exit 1
else
  echo "Slashed bonded tokens: pass"
fi

if [[ $unbonding_slashed -ne ${expected_slashed_unbonding%.*} ]]; then
  echo "Slashed unbonding tokens does not match expected value."
  exit 1
else
  echo "Slashed unbonding tokens: pass"
fi

if [[ $redelegation_dest_slashed -ne ${expected_slashed_redelegation%.*} ]]; then
  echo "Slashed redelegation tokens does not match expected value."
  exit 1
else
  echo "Slashed redelegation tokens: pass"
fi

sudo systemctl disable $LC_PROVIDER_SERVICE --now
sudo systemctl disable $LC_CONSUMER_SERVICE_1 --now
sudo systemctl disable $LC_CONSUMER_SERVICE_2 --now
rm -rf $LC_PROVIDER_HOME
rm -rf $LC_CONSUMER_HOME_1
rm -rf $LC_CONSUMER_HOME_2
sudo rm /etc/systemd/system/$LC_PROVIDER_SERVICE
sudo rm /etc/systemd/system/$LC_CONSUMER_SERVICE_1
sudo rm /etc/systemd/system/$LC_CONSUMER_SERVICE_2