#!/bin/bash 
# Test a gaia software upgrade via governance proposal.
# It assumes gaia is running on the local host.

gaia_host=$1
gaia_port=$2
upgrade_name=$3

echo "*** PRE-UPGRADE LOGS ***"
printf "\n\n*** val1 ***\n\n"
journalctl -u $PROVIDER_SERVICE_1 | tail -n 20
curl -s http://localhost:$VAL1_RPC_PORT/abci_info | jq '.'
printf "\n\n*** val2 ***\n\n"
journalctl -u $PROVIDER_SERVICE_2 | tail -n 20
curl -s http://localhost:$VAL2_RPC_PORT/abci_info | jq '.'
printf "\n\n*** val3 ***\n\n"
journalctl -u $PROVIDER_SERVICE_3 | tail -n 20
curl -s http://localhost:$VAL3_RPC_PORT/abci_info | jq '.'

echo "Attempting upgrade to $upgrade_name."

# Set time to wait for proposal to pass
# echo "Get voting_period from genesis file"
# voting_period=$(jq -r '.app_state.gov.voting_params.voting_period' $HOME_1/config/genesis.json)
# voting_period_seconds=${voting_period::-1}
voting_period_seconds=${VOTING_PERIOD::-1}
echo "Using ($voting_period_seconds)s voting period to calculate the upgrade height."
    
# Calculate upgrade height
echo "Calculate upgrade height"
block_time=1
let voting_blocks_delta=$voting_period_seconds/$block_time+3
height=$(curl -s http://$gaia_host:$gaia_port/block | jq -r .result.block.header.height)
upgrade_height=$(($height+$voting_blocks_delta))
echo "Upgrade block height set to $upgrade_height."

upgrade_info="{\"binaries\":{\"linux/amd64\":\"$DOWNLOAD_URL\"}}"
# Auto download: Set the binary paths need for the proposal message
if [ $COSMOS_SDK == "v45" ]; then
    proposal="$CHAIN_BINARY --output json tx gov submit-proposal software-upgrade $upgrade_name --from $WALLET_1 --keyring-backend test --upgrade-height $upgrade_height --upgrade-info $upgrade_info --title gaia-upgrade --description 'test' --chain-id $CHAIN_ID --deposit $VAL3_STAKE$DENOM --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT --yes --home $HOME_1"
elif [ $COSMOS_SDK == "v47" ]; then
    # Set up metadata
    jq -r --arg NAME "$upgrade_name" '.messages[0].plan.name |= $NAME' templates/proposal-software-upgrade.json > upgrade-1.json
    jq -r --arg HEIGHT "$upgrade_height" '.messages[0].plan.height |= $HEIGHT' upgrade-1.json > upgrade-2.json
    jq -r --arg INFO "$upgrade_info" '.messages[0].plan.info |= $INFO' upgrade-2.json > upgrade-3.json
    jq '.' upgrade-3.json
    proposal="$CHAIN_BINARY --output json tx gov submit-proposal upgrade-3.json --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT --yes --home $HOME_1"
fi
# Submit the proposal
echo "Submitting the upgrade proposal."
echo $proposal
txhash=$($proposal | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))

# Get proposal ID from txhash
echo "Getting proposal ID from txhash..."
proposal_id=$($CHAIN_BINARY --output json q tx $txhash --home $HOME_1 | jq -r '.logs[].events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value')
echo "Proposal ID: $proposal_id"

# Vote yes on the proposal
echo "Submitting the \"yes\" vote to proposal $proposal_id..."
vote="$CHAIN_BINARY tx gov vote $proposal_id yes --from $WALLET_1 --keyring-backend test --chain-id $CHAIN_ID --gas $GAS --gas-prices $GAS_PRICE$DENOM --gas-adjustment $GAS_ADJUSTMENT -y --home $HOME_1 -o json"
echo $vote
txhash=$($vote | jq -r .txhash)
sleep $(($COMMIT_TIMEOUT+2))
$CHAIN_BINARY q tx $txhash --home $HOME_1

# Wait for the voting period to be over
echo "Waiting for the voting period to end..."
sleep $VOTING_PERIOD

echo "Upgrade proposal $proposal_id status:"
$CHAIN_BINARY q gov proposal $proposal_id --output json --home $HOME_1 | jq '.status'

current_height=$(curl -s http://$gaia_host:$gaia_port/block | jq -r '.result.block.header.height')
blocks_delta=$(($upgrade_height-$current_height))

# Wait until the right height is reached
if [ "$COSMOVISOR" = true ]; then
    if [ "$UPGRADE_MECHANISM" = "cv_manual" ]; then
        mkdir -p $HOME_1/cosmovisor/upgrades/$upgrade_name/bin
        mkdir -p $HOME_2/cosmovisor/upgrades/$upgrade_name/bin
        mkdir -p $HOME_3/cosmovisor/upgrades/$upgrade_name/bin
        wget $DOWNLOAD_URL -O ./upgraded -q
        chmod +x ./upgraded
        cp ./upgraded $HOME_1/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY
        cp ./upgraded $HOME_2/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY
        cp ./upgraded $HOME_3/cosmovisor/upgrades/$upgrade_name/bin/$CHAIN_BINARY
    fi
    echo "Waiting for the upgrade to take place at block height $upgrade_height..."
    tests/test_block_production.sh $gaia_host $gaia_port $blocks_delta
    echo "The upgrade height was reached."

else
    echo "Waiting for the upgrade to take place at block height $upgrade_height..."
    tests/test_block_production.sh $gaia_host $gaia_port $blocks_delta
    echo "The upgrade height was reached."
    sleep $(($COMMIT_TIMEOUT*3))
    # Replace binary
    sudo systemctl stop $PROVIDER_SERVICE_1
    sudo systemctl stop $PROVIDER_SERVICE_2
    sudo systemctl stop $PROVIDER_SERVICE_3

    sudo apt install build-essential -y
    wget -q https://go.dev/dl/go1.22.4.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
    git clone https://github.com/cosmos/gaia.git
    cd gaia
    make install
    cd ..
    # wget $DOWNLOAD_URL -O ./upgraded -q
    # chmod +x ./upgraded
    # mv ./upgraded $HOME/go/bin/$CHAIN_BINARY
    sudo systemctl start $PROVIDER_SERVICE_1
    sudo systemctl start $PROVIDER_SERVICE_2
    sudo systemctl start $PROVIDER_SERVICE_3
fi

sleep 10

echo "Checking provider services are active..."
systemctl is-active --quiet $PROVIDER_SERVICE_1 && echo "$PROVIDER_SERVICE_1 is running"
systemctl is-active --quiet $PROVIDER_SERVICE_2 && echo "$PROVIDER_SERVICE_2 is running"
systemctl is-active --quiet $PROVIDER_SERVICE_3 && echo "$PROVIDER_SERVICE_3 is running"

printf "\n\n*** val1 ***\n\n"
journalctl -u $PROVIDER_SERVICE_1 | tail -n 150
curl -s http://localhost:$VAL1_RPC_PORT/abci_info | jq '.'
printf "\n\n*** val2 ***\n\n"
journalctl -u $PROVIDER_SERVICE_2 | tail -n 150
curl -s http://localhost:$VAL2_RPC_PORT/abci_info | jq '.'
printf "\n\n*** val3 ***\n\n"
journalctl -u $PROVIDER_SERVICE_3 | tail -n 150
curl -s http://localhost:$VAL3_RPC_PORT/abci_info | jq '.'