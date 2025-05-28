#!/bin/bash 
# Test a gaia software upgrade via governance proposal.
# It assumes gaia is running on the local host.

upgrade_name=$1

monikers=()
homes=()
rpc_ports=()
for i in $(seq -w 001 $validator_count)
do
    moniker=$moniker_prefix$i
    monikers+=($moniker)
    home=$home_prefix$i
    homes+=($home)
    rpc_port=$rpc_prefix$i
    rpc_ports+=($rpc_port)
done

if [ "$COSMOVISOR" = true ]; then
    if [ "$UPGRADE_MECHANISM" = "cv_manual" ]; then
        echo "> Using manual upgrade mechanism"
        mkdir -p ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin
        if [ "$BINARY_SOURCE" = "BUILD" ]; then
            echo "> Using Cosmovisor"
            echo "Building new binary."
            sudo apt install build-essential -y
            wget -q https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
            sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go$GO_VERSION.linux-amd64.tar.gz
            rm -rf gaia
            git clone https://github.com/cosmos/gaia.git
            cd gaia
            git checkout $TARGET_VERSION
            make install
            cd ..
            for i in $(seq 0 $[$validator_count-1])
            do
                cp $HOME/go/bin/gaiad ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY_NAME
            done
        else
            echo "Downloading new binary."
            wget $DOWNLOAD_URL -O ./upgraded -q
            chmod +x ./upgraded
            for i in $(seq 0 $[$validator_count-1])
            do
                cp ./upgraded ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY_NAME
            done                
        fi
    fi
fi

echo "Attempting upgrade to $upgrade_name."

# Set time to wait for proposal to pass
# echo "Get voting_period from genesis file"
# voting_period=$(jq -r '.app_state.gov.voting_params.voting_period' $HOME_1/config/genesis.json)
echo "Using ($VOTING_PERIOD)s voting period to calculate the upgrade height."
    
# Calculate upgrade height
echo "Calculate upgrade height"
block_time=1
let voting_blocks_delta=$voting_period_seconds/$block_time+5
height=$(curl -s http://127.0.0.1:${rpc_ports[0]}/block | jq -r .result.block.header.height)
upgrade_height=$(($height+$voting_blocks_delta))
echo "Upgrade block height set to $upgrade_height."

upgrade_info="{\"binaries\":{\"linux/amd64\":\"$DOWNLOAD_URL\"}}"
echo "Starting proposal:"
jq '.' templates/proposal-software-upgrade.json
# Set up metadata
jq -r --arg NAME "$upgrade_name" '.messages[0].plan.name |= $NAME' templates/proposal-software-upgrade.json > upgrade-1.json
jq -r --arg HEIGHT "$upgrade_height" '.messages[0].plan.height |= $HEIGHT' upgrade-1.json > upgrade-2.json
jq -r --arg INFO "$upgrade_info" '.messages[0].plan.info |= $INFO' upgrade-2.json > upgrade-3.json
jq -r '.expedited |= false' upgrade-3.json > upgrade-4.json
echo "Modified proposal:"
jq '.' upgrade-4.json
proposal="$CHAIN_BINARY --output json tx gov submit-proposal upgrade-4.json --from ${monikers[0]} --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --yes --home ${homes[0]}"


# Submit the proposal
echo "Submitting the upgrade proposal."
echo $proposal
txhash=$($proposal | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home ${homes[0]} | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "Proposal ID: $proposal_id"

# Vote yes on the proposal
echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from ${monikers[0]} --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home ${homes[0]} -o json"
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $txhash --home ${homes[0]}

# Wait for the voting period to be over
echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

echo "Upgrade proposal $proposal_id status:"
$CHAIN_BINARY q gov proposal $proposal_id --output json --home ${homes[0]} | jq '.proposal.status'

current_height=$(curl -s http://127.0.0.1:${rpc_ports[0]}/block | jq -r '.result.block.header.height')
blocks_delta=$(($upgrade_height-$current_height))

# Wait until the right height is reached
echo "Waiting for the upgrade to take place at block height $upgrade_height..."
tests/test_block_production.sh 127.0.0.1 ${rpc_ports[0]} $blocks_delta 100
echo "The upgrade height was reached."
if [ "$COSMOVISOR" = true ]; then
    echo "> Cosmovisor-run upgrade."
else
    # Replace binary
    sudo systemctl stop $PROVIDER_SERVICE_1
    sudo systemctl stop $PROVIDER_SERVICE_2
    sudo systemctl stop $PROVIDER_SERVICE_3

    if [ "$BINARY_SOURCE" = "BUILD" ]; then
        # Build
        sudo apt install build-essential -y
        wget -q https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go$GO_VERSION.linux-amd64.tar.gz
        rm -rf gaia
        git clone https://github.com/cosmos/gaia.git
        cd gaia
        git checkout $TARGET_VERSION
        make install
        cd ..
    else
        # Download
        echo "Downloading new binary..."
        wget $DOWNLOAD_URL -O ./upgraded -q
        chmod +x ./upgraded
        mv ./upgraded $HOME/go/bin/$CHAIN_BINARY
    fi

    sudo systemctl start $PROVIDER_SERVICE_1
    sudo systemctl start $PROVIDER_SERVICE_2
    sudo systemctl start $PROVIDER_SERVICE_3
fi

sleep 10

# echo "Checking provider services are active..."
# systemctl is-active --quiet $PROVIDER_SERVICE_1 && echo "$PROVIDER_SERVICE_1 is running"
# systemctl is-active --quiet $PROVIDER_SERVICE_2 && echo "$PROVIDER_SERVICE_2 is running"
# systemctl is-active --quiet $PROVIDER_SERVICE_3 && echo "$PROVIDER_SERVICE_3 is running"

# printf "\n\n*** val1 ***\n\n"
# journalctl -u $PROVIDER_SERVICE_1 | tail -n 150
# curl -s http://localhost:$VAL1_RPC_PORT/abci_info | jq '.'
# printf "\n\n*** val2 ***\n\n"
# journalctl -u $PROVIDER_SERVICE_2 | tail -n 150
# curl -s http://localhost:$VAL2_RPC_PORT/abci_info | jq '.'
# printf "\n\n*** val3 ***\n\n"
# journalctl -u $PROVIDER_SERVICE_3 | tail -n 150
# curl -s http://localhost:$VAL3_RPC_PORT/abci_info | jq '.'