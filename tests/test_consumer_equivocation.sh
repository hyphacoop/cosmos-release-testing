#!/bin/bash

expanded_count=$(( $validator_count+1 ))

echo "> Creating arrays"
monikers=()
homes=()
api_ports=()
rpc_ports=()
p2p_ports=()
grpc_ports=()
pprof_ports=()
logs=()
wallets=()
for i in $(seq -w 01 $expanded_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
    api_port=$api_prefix$i
    api_ports+=($api_port)
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
    p2p_port=$p2p_prefix$i
    p2p_ports+=($p2p_port)
    grpc_port=$grpc_prefix$i
    grpc_ports+=($grpc_port)
    pprof_port=$pprof_prefix$i
    pprof_ports+=($pprof_port)
    log=$log_prefix$i
    logs+=($log)
done

echo "> Configuring provider node"
peer_id=$($CHAIN_BINARY comet show-node-id --home ${homes[1]})
peer="$peer_id@127.0.0.1:${p2p_ports[1]}"

for (( i=$validator_count; i<$expanded_count; i++ ))
do
    echo "> Home $i"
    $CHAIN_BINARY config set client chain-id $CHAIN_ID --home ${homes[i]}
    $CHAIN_BINARY config set client keyring-backend test --home ${homes[i]}
    $CHAIN_BINARY config set client broadcast-mode sync --home ${homes[i]}
    $CHAIN_BINARY config set client node tcp://localhost:${rpc_ports[i]} --home ${homes[i]}
    $CHAIN_BINARY init ${monikers[i]} --chain-id $CHAIN_ID --home ${homes[i]} &> /dev/null

    toml set --toml-path ${homes[i]}/config/app.toml minimum-gas-prices "$GAS_PRICE"
    toml set --toml-path ${homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${homes[i]}/config/app.toml api.enabled-unsafe-cors true
    toml set --toml-path ${homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${api_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc.address "0.0.0.0:${grpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/app.toml grpc-web.enable false

    toml set --toml-path ${homes[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${rpc_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${pprof_ports[i]}"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${p2p_ports[i]}"
    sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' ${homes[i]}/config/config.toml
    sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${homes[i]}/config/config.toml
    toml set --toml-path ${homes[i]}/config/config.toml block_sync false
    toml set --toml-path ${homes[i]}/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers ""
    
    echo "> Set peer"
    toml set --toml-path ${homes[i]}/config/config.toml p2p.persistent_peers "$peer"
done

echo "> Copy snapshot from whale"
session=${monikers[0]}
echo "> Session: $session"
tmux send-keys -t $session C-c
cp ${homes[-1]}/data/priv_validator_state.json ./state.bak

cp -r ${homes[0]}/data ${homes[-1]}/
cp ./state.bak ${homes[-1]}/data/priv_validator_state.json
cp ${homes[0]}/config/genesis.json ${homes[-1]}/config/genesis.json
tmux new-session -d -s $session "$CHAIN_BINARY start --home ${homes[0]} 2>&1 | tee ${logs[0]}"
tmux new-session -d -s ${monikers[-1]} "$CHAIN_BINARY start --home ${homes[-1]} 2>&1 | tee ${logs[-1]}"
sleep 20

eqwallet=$($CHAIN_BINARY keys add eqval --home ${homes[-1]} --output json | jq -r '.address')
echo "> New wallet: $eqwallet"
echo "> Fund new validator"
$CHAIN_BINARY tx bank send $WALLET_1 $eqwallet $VAL_WHALE$DENOM --home $whale_home --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE -y -o json | jq '.'
sleep $(($COMMIT_TIMEOUT*2))
pubkey=$($CHAIN_BINARY comet show-validator --home ${homes[-1]})
amount=$VAL_STAKE$DENOM

jq --argjson pubkey "$pubkey" '.pubkey |= $pubkey' templates/create-validator.json > eqval.json
jq '.moniker |= "eqval"' eqval.json > eqval-moniker.json
cp eqval-moniker.json eqval.json
jq '.moniker |= "eqval"' eqval.json > eqval-moniker.json
cp eqval-moniker.json eqval.json
jq --arg amount "$amount" '.amount |= $amount' eqval.json > eqval-stake.json
cp eqval-stake.json eqval.json

jq '.' eqval.json
echo "> Create validator"
$CHAIN_BINARY tx staking create-validator eqval.json --from $eqwallet --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[-1]} -y
sleep $(($COMMIT_TIMEOUT*2))
status=$($CHAIN_BINARY q staking validators --home $whale_home -o json | jq -r '.validators[] | select(.description.moniker == "eqval").status')
if [ $status == "BOND_STATUS_BONDED" ]; then
  echo "> Validator was created successfully."
else
  echo "> Validator was not created successfully."
  exit 1
fi

# Consumer nodes
expanded_count=$(( $validator_count+2 ))

consumer_monikers=()
consumer_homes=()
consumer_api_ports=()
consumer_rpc_ports=()
consumer_p2p_ports=()
consumer_grpc_ports=()
consumer_pprof_ports=()
consumer_logs=()
for i in $(seq -w 01 $expanded_count)
do
    consumer_moniker=$consumer_moniker_prefix$i
    consumer_monikers+=($consumer_moniker)
    consumer_home=$consumer_home_prefix$i
    consumer_homes+=($consumer_home)
    consumer_api_port=$consumer_api_prefix$i
    consumer_api_ports+=($consumer_api_port)
    consumer_rpc_port=$consumer_rpc_prefix$i
    consumer_rpc_ports+=($consumer_rpc_port)
    consumer_p2p_port=$consumer_p2p_prefix$i
    consumer_p2p_ports+=($consumer_p2p_port)
    consumer_grpc_port=$consumer_grpc_prefix$i
    consumer_grpc_ports+=($consumer_grpc_port)
    consumer_pprof_port=$consumer_pprof_prefix$i
    consumer_pprof_ports+=($consumer_pprof_port)
    consumer_log=$consumer_log_prefix$i
    consumer_logs+=($consumer_log)
done

echo "> Configuring consumer nodes"
peer_a_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes[1]})
peer_a="$peer_a_id@127.0.0.1:${consumer_p2p_ports[1]}"
peer_b_id=$($CONSUMER_CHAIN_BINARY tendermint show-node-id --home ${consumer_homes[2]})
peer_b="$peer_b_id@127.0.0.1:${consumer_p2p_ports[2]}"


for (( i=$validator_count; i<$expanded_count; i++ ))
do
    echo "> Home $i"
    $CONSUMER_CHAIN_BINARY config set client chain-id $CONSUMER_CHAIN_ID --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config set client keyring-backend test --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config set client broadcast-mode sync --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY config set client node tcp://localhost:${consumer_rpc_ports[i]} --home ${consumer_homes[i]}
    $CONSUMER_CHAIN_BINARY init ${consumer_monikers[i]} --chain-id $CONSUMER_CHAIN_ID --home ${consumer_homes[i]} &> /dev/null

    toml set --toml-path ${consumer_homes[i]}/config/app.toml minimum-gas-prices "$CONSUMER_GAS_PRICE"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.enable true
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.enabled-unsafe-cors true
    echo "> Consumer api: tcp://0.0.0.0:${consumer_api_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml api.address "tcp://0.0.0.0:${consumer_api_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml grpc.address "0.0.0.0:${consumer_grpc_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/app.toml grpc-web.enable false

    toml set --toml-path ${consumer_homes[i]}/config/config.toml rpc.laddr "tcp://0.0.0.0:${consumer_rpc_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml rpc.pprof_laddr "0.0.0.0:${consumer_pprof_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.laddr "tcp://0.0.0.0:${consumer_p2p_ports[i]}"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.pex false
    sed -i -e '/allow_duplicate_ip =/ s/= .*/= true/' ${consumer_homes[i]}/config/config.toml
    sed -i -e '/addr_book_strict =/ s/= .*/= false/' ${consumer_homes[i]}/config/config.toml
    toml set --toml-path ${consumer_homes[i]}/config/config.toml block_sync false
    toml set --toml-path ${consumer_homes[i]}/config/config.toml consensus.timeout_commit "${COMMIT_TIMEOUT}s"
    toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers ""
    if [ $i == $validator_count ]; then
        echo "> Set peer A"
        toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers "$peer_a"
    else
        echo "> Set peer B"
        toml set --toml-path ${consumer_homes[i]}/config/config.toml p2p.persistent_peers "$peer_b"
    fi
done

echo "> Opt in with new validator."
consumer_pubkey=$($CONSUMER_CHAIN_BINARY tendermint show-validator --home ${consumer_homes[-2]})
consumer_id=$($CHAIN_BINARY q provider list-consumer-chains --home $whale_home -o json | jq -r --arg chainid "$CONSUMER_CHAIN_ID" '.chains[] | select(.chain_id == $chainid).consumer_id')
echo "> Consumer id: $consumer_id, pubkey: $consumer_pubkey"
$CHAIN_BINARY tx provider opt-in $consumer_id $consumer_pubkey --from $eqwallet --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[-1]} -y
sleep $(($COMMIT_TIMEOUT*3))

echo "> Copy snapshot from whale"
session=${consumer_monikers[0]}
echo "> Session: $session"
tmux send-keys -t $session C-c
cp ${consumer_homes[-2]}/data/priv_validator_state.json ./state.bak

cp -r ${consumer_homes[0]}/data ${consumer_homes[-2]}/
cp -r ${consumer_homes[0]}/data ${consumer_homes[-1]}/
cp ./state.bak ${consumer_homes[-2]}/data/priv_validator_state.json
cp ./state.bak ${consumer_homes[-1]}/data/priv_validator_state.json
cp ${consumer_homes[0]}/config/genesis.json ${consumer_homes[-2]}/config/genesis.json
cp ${consumer_homes[0]}/config/genesis.json ${consumer_homes[-1]}/config/genesis.json

echo "> Duplicate validator key"
cp ${consumer_homes[-2]}/config/priv_validator_key.json ${consumer_homes[-1]}/config/priv_validator_key.json


tmux new-session -d -s ${consumer_monikers[-2]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-2]} 2>&1 | tee ${consumer_logs[-2]}"
tmux new-session -d -s ${consumer_monikers[-1]} "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[-1]} 2>&1 | tee ${consumer_logs[-1]}"
sleep $(($COMMIT_TIMEOUT*20))
tmux new-session -d -s $session "$CONSUMER_CHAIN_BINARY start --home ${consumer_homes[0]} 2>&1 | tee ${consumer_logs[0]}"
sleep $(($COMMIT_TIMEOUT*30))
echo "> Whale node:"
tail ${consumer_logs[0]} -n 50
echo "> Node A (${consumer_monikers[-2]}):"
cat ${consumer_logs[-2]} -n 100
echo "> Node B (${consumer_monikers[-1]}):"
tail ${consumer_logs[-1]} -n 100

echo "> Consumer:"
$CONSUMER_CHAIN_BINARY q slashing signing-infos --home ${consumer_whale_home}
echo "> Provider:"
$CHAIN_BINARY q slashing signing-infos --home ${whale_home}

consensus_address=$($CONSUMER_CHAIN_BINARY tendermint show-address --home ${consumer_homes[-2]})
echo "> Consumer consensus address: $consensus_address"
$CONSUMER_CHAIN_BINARY q evidence list --home $consumer_whale_home -o json | jq '.'
validator_check=$($CONSUMER_CHAIN_BINARY q evidence list --home $consumer_whale_home -o json | jq '.' | grep $consensus_address)
echo $validator_check
if [ -z "$validator_check" ]; then
  echo "No equivocation evidence found."
  exit 1
else
  echo "Equivocation evidence found!"
fi
echo "> Collecting infraction height."
height=$($CONSUMER_CHAIN_BINARY q evidence list --home $consumer_whale_home -o json | jq -r '.evidence[0].value.height')
echo "> Evidence height: $height"
sleep $(($COMMIT_TIMEOUT*3))

echo "> Collecting evidence around the infraction height in consumer chain."
evidence_block=$(($height+2))
echo "> 1"
$CONSUMER_CHAIN_BINARY q block --type=height $evidence_block --home $consumer_whale_home -o json | jq '.'
echo "> 2"
$CONSUMER_CHAIN_BINARY q block --type=height $evidence_block --home $consumer_whale_home -o json | jq '.evidence'
echo "> 3"
$CONSUMER_CHAIN_BINARY q block --type=height $evidence_block --home $consumer_whale_home -o json | jq '.evidence.evidence'
echo "> 4"
$CONSUMER_CHAIN_BINARY q block --type=height $evidence_block --home $consumer_whale_home -o json | jq '.evidence.evidence[0].duplicate_vote_evidence'

$CONSUMER_CHAIN_BINARY q block --type=height $evidence_block --home $consumer_whale_home -o json | jq '.evidence.evidence[0].duplicate_vote_evidence' > evidence.json
echo "> Starting evidence JSON:"
jq '.' evidence.json
scripts/prepare_evidence.sh evidence.json

echo "> Collecting IBC header at infraction height in consumer chain."
$CONSUMER_CHAIN_BINARY q ibc client header --height $height --home $consumer_whale_home -o json | jq '.' > ibc-header.json
echo "> Starting IBC header JSON:"
jq '.' ibc-header.json
scripts/prepare_infraction_header.sh ibc-header.json

echo "> Submitting double voting evidence tx"
$CHAIN_BINARY tx provider submit-consumer-double-voting $consumer_id evidence.json ibc-header.json --from $WALLET_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE --home ${homes[0]} -y
sleep $(($COMMIT_TIMEOUT*2))
echo "> Provider:"
address=$($CHAIN_BINARY comet show-address --home ${homes[-1]})
echo "> Address: $address"
$CHAIN_BINARY q slashing signing-infos --home ${whale_home} -o json | jq '.'
tombstoned=$($CHAIN_BINARY q slashing signing-infos --home ${whale_home} -o json | jq -r --arg addr "$address" '.info[] | select(.address==$addr).tombstoned')
echo "> Tombstoned: $tombstoned"
tmux send-keys -t ${consumer_monikers[-1]} C-c
tmux send-keys -t ${consumer_monikers[-2]} C-c
tmux send-keys -t ${monikers[-1]} C-c
rm -r ${consumer_homes[-2]}
rm -r ${consumer_homes[-1]}
rm -r ${homes[-1]}

if [[ "$tombstoned" == "true" ]]; then
    echo "> PASS: Validator has been tombstoned."
else
    echo "> FAIL: Validator has not been tombstoned."
    exit 1
fi
