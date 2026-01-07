#!/bin/bash

echo "> Storing channel IDs"
# provider->pfm1
source scripts/vars.sh
pfm_ab_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="pfm1").client_id')
echo "> A-B client ID: $pfm_ab_client_id"
pfm_ab_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_ab_client_id" '.connections[] | select(.client_id==$client).id')
echo "> A-B connection ID: $pfm_ab_connection_id"
pfm_ab_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_ab_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> A-B channel ID: $pfm_ab_channel_id"
              
# pfm1->pfm2
source scripts/vars_pfm_1.sh
pfm_bc_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="pfm2").client_id')
echo "> B-C client ID: $pfm_bc_client_id"
pfm_bc_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_bc_client_id" '.connections[] | select(.client_id==$client).id')
echo "> B-C connection ID: $pfm_bc_connection_id"
pfm_bc_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_bc_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> B-C channel ID: $pfm_bc_channel_id"

# pfm2->pfm3
source scripts/vars_pfm_2.sh
pfm_cd_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="pfm3").client_id')
echo "> C-D client ID: $pfm_cd_client_id"
pfm_cd_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_cd_client_id" '.connections[] | select(.client_id==$client).id')
echo "> C-D connection ID: $pfm_cd_connection_id"
pfm_cd_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_cd_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> C-D channel ID: $pfm_cd_channel_id"

# pfm3->pfm2
source scripts/vars_pfm_3.sh
pfm_dc_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="pfm2").client_id')
echo "> D-C client ID: $pfm_dc_client_id"
pfm_dc_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_dc_client_id" '.connections[] | select(.client_id==$client).id')
echo "> D-C connection ID: $pfm_dc_connection_id"
pfm_dc_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_dc_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> D-C channel ID: $pfm_dc_channel_id"

# pfm2->pfm1
source scripts/vars_pfm_2.sh
pfm_cb_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="pfm1").client_id')
echo "> C-B client ID: $pfm_cb_client_id"
pfm_cb_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_cb_client_id" '.connections[] | select(.client_id==$client).id')
echo "> C-B connection ID: $pfm_cb_connection_id"
pfm_cb_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_cb_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> C-B channel ID: $pfm_cb_channel_id"

# pfm1->provider
source scripts/vars_pfm_1.sh
pfm_ba_client_id=$($CHAIN_BINARY q ibc client states -o json --home $whale_home | jq -r '.client_states[] | select(.client_state.chain_id=="testnet").client_id')
echo "> B-A client ID: $pfm_ba_client_id"
pfm_ba_connection_id=$($CHAIN_BINARY q ibc connection connections -o json --home $whale_home | jq -r --arg client "$pfm_ba_client_id" '.connections[] | select(.client_id==$client).id')
echo "> B-A connection ID: $pfm_ba_connection_id"
pfm_ba_channel_id=$($CHAIN_BINARY q ibc channel connections $pfm_ba_connection_id -o json --home $whale_home | jq -r '.channels[] | select(.port_id=="transfer").channel_id')
echo "> B-A channel ID: $pfm_ba_channel_id"
              
echo "pfm_ab_channel_id=$pfm_ab_channel_id" >> $GITHUB_ENV
echo "pfm_bc_channel_id=$pfm_bc_channel_id" >> $GITHUB_ENV
echo "pfm_cd_channel_id=$pfm_cd_channel_id" >> $GITHUB_ENV
echo "pfm_dc_channel_id=$pfm_dc_channel_id" >> $GITHUB_ENV
echo "pfm_cb_channel_id=$pfm_cb_channel_id" >> $GITHUB_ENV
echo "pfm_ba_channel_id=$pfm_ba_channel_id" >> $GITHUB_ENV
