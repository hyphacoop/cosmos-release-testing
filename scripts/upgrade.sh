#!/bin/bash 
# Test a gaia software upgrade via governance proposal.
# It assumes gaia is running on the local host.

upgrade_name=$1

homes=()
logs=()
for i in $(seq -w 01 $validator_count)
do
    home=$home_prefix$i
    homes+=($home)
    log=$log_prefix$i
    logs+=($log)
done

if [ "$COSMOVISOR" = true ]; then
    if [ "$UPGRADE_MECHANISM" = "cv_manual" ]; then
        echo "> Using manual upgrade mechanism"
        if [ "$BINARY_SOURCE" = "BUILD" ]; then
            echo "> Using Cosmovisor"
            echo "Building new binary."
            sudo apt install build-essential -y
            wget -q https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
            sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go$GO_VERSION.linux-amd64.tar.gz
            rm -rf gaia
            git clone https://github.com/cosmos/gaia.git
            # cd gaia
            pushd gaia
            git checkout $TARGET_VERSION
            make install
            # cd ..
            popd
            cp $HOME/go/bin/gaiad $CHAIN_BINARY
            for i in $(seq 0 $[$validator_count-1])
            do
                mkdir -p ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin
                cp $HOME/go/bin/gaiad ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY_NAME
            done
        else
            echo "Downloading new binary."
            wget $DOWNLOAD_URL -O ./upgraded -q
            chmod +x ./upgraded
            for i in $(seq 0 $[$validator_count-1])
            do
                mkdir -p ${homes[i]}/cosmovisor/upgrades/$upgrade_name/bin
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
block_time=$COMMIT_TIMEOUT
let voting_blocks_delta=$VOTING_PERIOD/$block_time+5
height=$(curl -s http://127.0.0.1:$whale_rpc/block | jq -r .result.block.header.height)
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
proposal="$CHAIN_BINARY --output json tx gov submit-proposal upgrade-4.json --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT --yes --home $whale_home"


# Submit the proposal
echo "Submitting the upgrade proposal."
echo $proposal
txhash=$($proposal | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $whale_home | jq -r '.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')

echo "Proposal ID: $proposal_id"

# Vote yes on the proposal
echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json"
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $txhash --home $whale_home

# Wait for the voting period to be over
echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

echo "Upgrade proposal $proposal_id status:"
$CHAIN_BINARY q gov proposal $proposal_id --output json --home $whale_home | jq '.proposal.status'

current_height=$(curl -s http://127.0.0.1:$whale_rpc/block | jq -r '.result.block.header.height')
blocks_delta=$(($upgrade_height-$current_height))

# Wait until the right height is reached
echo "Waiting for the upgrade to take place at block height $upgrade_height..."
tests/test_block_production.sh 127.0.0.1 $whale_rpc $blocks_delta 50
echo "> Validator log:"
tail -n 50 ${logs[0]}

echo "The upgrade height was reached."
if [ "$COSMOVISOR" = true ]; then
    echo "> Cosmovisor-run upgrade."

else
    ./$STOP_SCRIPT
    sleep 5
    if [ "$BINARY_SOURCE" = "BUILD" ]; then
        # Build
        sudo apt install build-essential -y
        wget -q https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go$GO_VERSION.linux-amd64.tar.gz
        rm -rf gaia
        git clone https://github.com/cosmos/gaia.git
        # cd gaia
        pushd gaiad
        git checkout $TARGET_VERSION
        make install
        # cd ..
        popd
        cp $HOME/go/bin/gaiad $CHAIN_BINARY
    else
        # Download
        echo "Downloading new binary..."
        wget $DOWNLOAD_URL -O ./upgraded -q
        chmod +x ./upgraded
        mv ./upgraded $CHAIN_BINARY
    fi
    ls -la
    ./$START_SCRIPT
fi

sleep 10

echo "> Validator log:"
tail -n 50 ${logs[0]}
