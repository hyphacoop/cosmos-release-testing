#!/bin/bash 
# Test a gaia software upgrade via binary swap.
# It assumes gaia is running on the local host.

gaia_host=$1
gaia_port=$2

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

# Replace binary
sudo systemctl stop $PROVIDER_SERVICE_1
sudo systemctl stop $PROVIDER_SERVICE_2
sudo systemctl stop $PROVIDER_SERVICE_3

echo "> Downloading new binary"
echo "URL: $DOWNLOAD_URL" 
wget $DOWNLOAD_URL -O ./upgraded -q
chmod +x ./upgraded
./upgraded version --long

if [ "$PARTIAL_UPGRADE" = true ]; then
    mv ./upgraded $HOME/go/bin/$CHAIN_BINARY_PARTIAL
else
    mv ./upgraded $HOME/go/bin/$CHAIN_BINARY
fi

sudo systemctl start $PROVIDER_SERVICE_1
sudo systemctl start $PROVIDER_SERVICE_2
sudo systemctl start $PROVIDER_SERVICE_3


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

echo "> Validators:"
$CHAIN_BINARY q staking validators -o json --home $HOME_1 | jq '.'