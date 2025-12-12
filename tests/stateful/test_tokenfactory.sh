#!/bin/bash
set -e

mint_token=1000000000000000
bank_send=2000000000$DENOM
tf_denom_name="cake"

# Create a tokenfactory wallet
echo "[INFO]: Creating wallet for tokenfactory..."
tokenfactory_wallet1_json=$($CHAIN_BINARY --home $HOME_1 keys add tokenfactory-1 --output json)
echo "[INFO]: tokenfactory_wallet1_json: $tokenfactory_wallet1_json"
tokenfactory_wallet1_addr=$(echo $tokenfactory_wallet1_json | jq -r '.address')

# Create denom
echo "[INFO]: Create denom: $tf_denom_name"
$CHAIN_BINARY --home $HOME_1 tx tokenfactory create-denom $tf_denom_name --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10


# query denom by admin
echo "[INFO]: Get denom by admin"
$CHAIN_BINARY --home $HOME_1 q tokenfactory denoms-from-admin $WALLET_1
tf_token1=$($CHAIN_BINARY --home $HOME_1 q tokenfactory denoms-from-admin $$WALLET_1 -o json | jq -r '.denoms[0]')
echo "[DEBUG]: tf_token: $tf_token"

# Mint token to tokenfactory-1
echo "[INFO]: Mint tokens to tokenfactory-1: $tokenfactory_wallet1_addr"
$CHAIN_BINARY --home $HOME_1 tx tokenfactory mint-to $tokenfactory_wallet1_addr $mint_token$tf_token1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

# Mint token to val wallet
echo "[INFO]: Mint tokens to val: $WALLET_1"
$CHAIN_BINARY --home $HOME_1 tx tokenfactory mint-to $WALLET_1 $mint_token$tf_token1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

# Verify tokens in wallets
echo "[INFO]: Verify minted tokens in $WALLET_1"
val_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")

echo "[INFO]: Verify minted tokens in $tokenfactory_wallet1_addr"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
