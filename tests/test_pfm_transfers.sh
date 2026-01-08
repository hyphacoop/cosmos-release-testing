#!/bin/bash
source scripts/vars_pfm_3.sh
# channel_provider=$($CHAIN_BINARY q ibc channel end transfer channel-0 --home $whale_home --output json | jq -r '.channel.counterparty.channel_id')

echo "Provider chain channel ID: $pfm_ab_channel_id"

# IBC denom derivation
# A-D: provider -> pfm 1 -> pfm 2 -> pfm-3 (A->D)
# 1. Receiving channel in pfm3
# 2. Receiving channel in pfm2
# 3. Receiving channel in pfm1
# 4. Denom in provider
ad_receive_path=transfer/$pfm_dc_channel_id/transfer/$pfm_cb_channel_id/transfer/$pfm_ba_channel_id/$DENOM
echo "A-D path: $ad_receive_path"
target_denom_a_d=ibc/$(echo -n $ad_receive_path | shasum -a 256 | cut -d ' ' -f1 | tr '[a-z]' '[A-Z]')

# D-A: provider <- pfm 1 <- pfm 2 <- pfm-3 (D->A)
# 1. Receiving channel in provider
# 2. Receiving channel in pfm1
# 3. Receiving channel in pfm2
# 4. Denom in pfm3
da_receive_path=transfer/$pfm_ab_channel_id/transfer/$pfm_bc_channel_id/transfer/$pfm_cd_channel_id/$DENOM
echo "D-A path: $da_receive_path"
target_denom_d_a=ibc/$(echo -n $da_receive_path | shasum -a 256 | cut -d ' ' -f1 | tr '[a-z]' '[A-Z]')
echo "Target denom A->D: $target_denom_a_d"
echo "Target denom D->A: $target_denom_d_a"

d_start_balance=$($CHAIN_BINARY --home $whale_home q bank balances $WALLET_1 -o json | jq -r --arg DENOM "$target_denom_a_d" '.balances[] | select(.denom==$DENOM).amount')
if [ -z "$d_start_balance" ]; then
  d_start_balance=0
fi
echo "Chain D starting balance in expected denom: $d_start_balance"

source scripts/vars.sh
# PFM path
# A-D: provider -> pfm 1 -> pfm 2 -> pfm-3 (A->D)
# 1. Sending channel in provider (transfer channel)
# 2. Sending channel in pfm1 (first forward)
# 3. Sending channel in pfm2 (second forward)
txhash=$($CHAIN_BINARY tx ibc-transfer transfer transfer $pfm_ab_channel_id "pfm" --memo "{\"forward\": {\"receiver\": \"pfm\",\"port\": \"transfer\",\"channel\": \"$pfm_bc_channel_id\",\"timeout\": \"10m\",\"next\": {\"forward\": {\"receiver\": \"$WALLET_1\",\"port\": \"transfer\",\"channel\":\"$pfm_cd_channel_id\",\"timeout\":\"10m\"}}}}" 1000000$DENOM --from $WALLET_1 --gas auto --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home -o json | jq -r '.txhash')
echo "Waiting for the transfer to reach chain D..."
date
sleep $(($COMMIT_TIMEOUT+60))
date
# echo "> Tx hash query:"
# $CHAIN_BINARY q tx $txhash -o json --home $HOME_1 | jq '.'
# $CHAIN_BINARY --home $whale_home q bank balances $WALLET_1
# $CHAIN_BINARY --home $whale_home q bank balances $WALLET_1 -o json | jq -r '.'

source scripts/vars_pfm_3.sh
$CHAIN_BINARY --home $whale_home q bank balances $WALLET_1
d_end_balance=$($CHAIN_BINARY --home $whale_home q bank balances $WALLET_1 -o json | jq -r --arg DENOM "$target_denom_a_d" '.balances[] | select(.denom==$DENOM).amount')
if [ -z "$d_end_balance" ]; then
  d_end_balance=0
fi
echo "Chain D ending balance in expected denom: $d_end_balance"

if [ $d_end_balance -gt $d_start_balance ]; then
  echo "Chain D balance has increased!"
else
  echo "Chain D balance has not increased!"
  cat relayer.log
  # journalctl -u $RELAYER.service | tail -n 100
  exit 1
fi

source scripts/vars.sh
a_start_balance=$($CHAIN_BINARY --home $whale_home q bank balances $WALLET_1 -o json | jq -r --arg DENOM "$target_denom_d_a" '.balances[] | select(.denom==$DENOM).amount')
if [ -z "$a_start_balance" ]; then
  a_start_balance=0
fi
echo "Chain A starting balance in expected denom: $a_start_balance"

source scripts/vars_pfm_3.sh
# PFM path
# D-A: provider <- pfm 1  <- pfm 2 <- pfm-3 (D->A)
# 1. Sending channel in pfm3 (transfer channel)
# 2. Sending channel in pfm2 (first forward)
# 3. Sending channel in pfm1 (second forward)
$CHAIN_BINARY tx ibc-transfer transfer transfer $pfm_dc_channel_id "pfm" --memo "{\"forward\": {\"receiver\": \"pfm\",\"port\": \"transfer\",\"channel\": \"$pfm_cb_channel_id\",\"timeout\": \"10m\",\"next\": {\"forward\": {\"receiver\": \"$WALLET_1\",\"port\": \"transfer\",\"channel\":\"$pfm_ba_channel_id\",\"timeout\":\"10m\"}}}}" 1000000$DENOM --from $WALLET_1 --gas auto --gas-prices $GAS_PRICE --gas-adjustment $GAS_ADJUSTMENT -y --home $whale_home
echo "Waiting for the transfer to reach chain A..."
sleep $(($COMMIT_TIMEOUT+60))

source scripts/vars.sh
a_end_balance=$($CHAIN_BINARY --home $whale_home q bank balances $WALLET_1 -o json | jq -r --arg DENOM "$target_denom_d_a" '.balances[] | select(.denom==$DENOM).amount')
if [ -z "$a_end_balance" ]; then
  a_end_balance=0
fi
echo "Chain A ending balance in expected denom: $a_end_balance"

if [ $a_end_balance -gt $a_start_balance ]; then
  echo "Chain A balance has increased!"
else
  echo "Chain A balance has not increased!"
  # journalctl -u $RELAYER.service | tail -n 100
  cat relayer.log
  exit 1
fi
