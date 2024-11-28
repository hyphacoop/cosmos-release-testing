#!/bin/bash
# source vars.sh

monikers=()
homes=()
api_ports=()
rpc_ports=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
    api_port=$api_prefix$i
    api_ports+=($api_port)
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
done

echo "> Attempting upgrade to $UPGRADE_VERSION"
current_version=$(curl -s http://localhost:${rpc_ports[0]}/abci_info | jq -r '.result.response.version')
echo "> Current version: $current_version"
current_major_version=$(echo "$current_version" | grep -oP '(?<=v)[0-9]+')
echo "> Current major version: $current_major_version"
upgrade_major_version=$(echo "$UPGRADE_VERSION" | grep -oP '(?<=v)[0-9]+')
echo "> Upgrade major version: $upgrade_major_version"

major_upgrade=0
if [ "$upgrade_major_version" -gt "$current_major_version" ]; then
    echo "> Upgrade major version is greater than current major version."
    major_upgrade=1
fi

if [ "$major_upgrade" -eq 1 ]; then
    echo "> Major upgrade."
    upgrade_name="v${upgrade_major_version}"
    echo "> Upgrade name: $upgrade_name"
    let voting_blocks_delta=$VOTING_PERIOD/$TIMEOUT_COMMIT+5
    echo "> Voting blocks delta: $voting_blocks_delta"
    height=$(curl -s http://localhost:${rpc_ports[0]}/block | jq -r .result.block.header.height)
    upgrade_height=$(($height+$voting_blocks_delta))
    echo "> Upgrade height: $upgrade_height"
    min_deposit=$(curl -s http://localhost:${api_ports[0]}/cosmos/gov/v1/params/voting | jq -r '.params.min_deposit[0].amount')
    echo "> Minimum deposit: $min_deposit"
    echo "> Building proposal"
    echo "{
    \"messages\": [
     {
      \"@type\": \"/cosmos.upgrade.v1beta1.MsgSoftwareUpgrade\",
      \"authority\": \"cosmos10d07y265gmmuvt4z0w9aw880jnsr700j6zn9kn\",
      \"plan\": {
       \"name\": \"$upgrade_name\",
       \"time\": \"0001-01-01T00:00:00Z\",
       \"height\": \"$upgrade_height\",
       \"info\": \"\",
       \"upgraded_client_state\": null
      }
     }
    ],
    \"metadata\": \"ipfs://CID\",
    \"deposit\": \"$min_deposit$DENOM\",
    \"title\": \"Software Upgrade\",
    \"summary\": \"This will upgrade the chain software version\"
   }" > temp/upgrade-proposal.json

    proposal="$CHAIN_BINARY --output json tx gov submit-proposal temp/upgrade-proposal.json --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --yes --home ${homes[0]}"
    echo $proposal
    proposal_response=$($proposal | jq -r '.')
    txhash=$(echo $proposal_response | jq -r .txhash)
    echo "> TX hash for proposal submission: $txhash"
    sleep $[ $TIMEOUT_COMMIT+1 ]
    proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home ${homes[0]} | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
    echo "> Proposal ID: $proposal_id"
    echo "> Voting yes on proposal $proposal_id"
    vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home ${homes[0]} -o json"
    echo $vote
    txhash=$($vote | jq -r .txhash)
    sleep $[ $TIMEOUT_COMMIT+1 ]
    $CHAIN_BINARY q tx $txhash --home ${homes[0]}
    scripts/wait_for_block.sh $upgrade_height
    echo "> Upgrade height reached."
else
    echo "> Not a major upgrade."
fi

echo "> Stopping nodes"
scripts/stop.sh
sleep 3
if [ "$UPGRADE_BINARY_SOURCE" = "DOWNLOAD" ]; then
    echo "> Downloading binary"
    wget -q $UPGRADE_BINARY_URL -O $CHAIN_BINARY
    chmod +x $CHAIN_BINARY
elif [ "$UPGRADE_BINARY_SOURCE" = "BUILD" ]; then
    echo "> Building binary"
    git clone https://github.com/cosmos/gaia.git
    pushd gaia
    git checkout $UPGRADE_VERSION
    make build
    popd
    cp gaia/build/gaiad $CHAIN_BINARY
fi
echo "> Starting nodes"
scripts/start.sh
sleep 3
echo "> Check upgrade version."
current_version=$(curl -s http://localhost:${rpc_ports[0]}/abci_info | jq -r '.result.response.version')
echo "> Current version: $current_version"
if [ "$current_version" = "$UPGRADE_VERSION" ]; then
    echo "> Upgrade successful."
    exit 0
else
    echo "> Current version does not match target upgrade version."
    exit 1
fi