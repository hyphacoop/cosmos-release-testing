#!/bin/bash
set -e

mint_token=1000000000000000
bank_send=2000000000$DENOM
tf_denom_name="cake"
tf_bank_send=10000
tf_burn_amount=1000

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
tf_token1=$($CHAIN_BINARY --home $HOME_1 q tokenfactory denoms-from-admin $WALLET_1 -o json | jq -r '.denoms[0]')
echo "[DEBUG]: tf_token1: $tf_token1"

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
if [ $val_mint_token == $mint_token ]
then
    echo "[PASS]: Correct minted tokens in $WALLET_1: $val_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $WALLET_1 expected $mint_token$tf_token1 got $val_mint_token$tf_token1"
    exit 1
fi

echo "[INFO]: > Verify minted tokens in $tokenfactory_wallet1_addr"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
if [ $tokenfactory_wallet1_mint_token == $mint_token ]
then
    echo "[PASS]: Correct minted tokens in $tokenfactory_wallet1_addr: $val_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $tokenfactory_wallet1_addr expected $mint_token$tf_token1 got $val_mint_token$tf_token1"
    exit 1
fi

# test bank send of minted tokens
echo "[INFO]: > Test bank send minted tokens"
$CHAIN_BINARY --home $HOME_1 tx bank send $WALLET_1 $tokenfactory_wallet1_addr $tf_bank_send$tf_token1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[DEBUG]: verifying val wallet"
val_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
let expected_val_token=$mint_token-$tf_bank_send
echo "[DEBUG]: expecting: $expected_val_token"
if [ $val_mint_token == $expected_val_token ]
then
    echo "[PASS]: Correct minted tokens in $WALLET_1: $val_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $WALLET_1 expected $expected_val_token$tf_token1 got $val_mint_token$tf_token1"
    exit 1
fi

echo "[DEBUG]: verifying tokenfatory wallet"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
let expected_tokenfactory_wallet1_token=$mint_token+$tf_bank_send
echo "[DEBUG]: expecting: $expected_tokenfactory_wallet1_token"
if [ $tokenfactory_wallet1_mint_token == $expected_tokenfactory_wallet1_token ]
then
    echo "[PASS]: Correct minted tokens in $tokenfactory_wallet1_addr: $tokenfactory_wallet1_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $tokenfactory_wallet1_addr expected $expected_tokenfactory_wallet1_token$tf_token1 got $tokenfactory_wallet1_mint_token$tf_token1"
    exit 1
fi

# Test tokenfactory burn denom
echo "[INFO]: > Test tokenfactory burn denom"
echo "[DEBUG]: Try burning from non token admin"
set +e
$CHAIN_BINARY --home $HOME_1 tx tokenfactory burn $tf_burn_amount$tf_token1 --from $tokenfactory_wallet1_addr --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
set -e
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

if [ $? == 0 ]
then
    echo "[PASS]: TX failed from token non-admin"
else
    echo "[FAILED]: TX successful from token non-admin account"
fi
echo "[INFO]: Verify token value didn't change"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
let expected_tokenfactory_wallet1_token=$mint_token+$tf_bank_send
echo "[DEBUG]: expecting: $expected_tokenfactory_wallet1_token"
if [ $tokenfactory_wallet1_mint_token == $expected_tokenfactory_wallet1_token ]
then
    echo "[PASS]: Correct minted tokens in $tokenfactory_wallet1_addr: $tokenfactory_wallet1_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $tokenfactory_wallet1_addr expected $expected_tokenfactory_wallet1_token$tf_token1 got $tokenfactory_wallet1_mint_token$tf_token1"
    exit 1
fi

echo "[DEBUG]: Try burning from token admin"
last_val_mint_token=$val_mint_token
$CHAIN_BINARY --home $HOME_1 tx tokenfactory burn $tf_burn_amount$tf_token1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Verify token value changed"
val_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $WALLET_1 -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
let expected_val_token=$last_val_mint_token-$tf_burn_amount
echo "[DEBUG]: expecting: $expected_val_token"
if [ $val_mint_token == $expected_val_token ]
then
    echo "[PASS]: Correct minted tokens in $WALLET_1: $val_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $WALLET_1 expected $expected_val_token$tf_token1 got $val_mint_token$tf_token1"
    exit 1
fi

echo "[INFO]: > Test burn-from (this tx should fail)"
set +e
$CHAIN_BINARY --home $HOME_1 tx tokenfactory burn-from $tokenfactory_wallet1_addr $tf_burn_amount$tf_token1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
set -e
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

if [ $? == 0 ]
then
    echo "[PASS]: TX failed"
else
    echo "[FAILED]: TX successful but burn-from should be disabled"
fi
echo "[INFO]: Verify token value didn't change"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
echo "[DEBUG]: expecting: $expected_tokenfactory_wallet1_token"
if [ $tokenfactory_wallet1_mint_token == $expected_tokenfactory_wallet1_token ]
then
    echo "[PASS]: Correct minted tokens in $tokenfactory_wallet1_addr: $tokenfactory_wallet1_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $tokenfactory_wallet1_addr expected $expected_tokenfactory_wallet1_token$tf_token1 got $tokenfactory_wallet1_mint_token$tf_token1"
    exit 1
fi

echo "[INFO]: > Test force-transfer (this tx should fail)"
set +e
$CHAIN_BINARY --home $HOME_1 tx tokenfactory force-transfer $tf_burn_amount$tf_token1 $tokenfactory_wallet1_addr $WALLET_1 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
set -e
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

if [ $? == 0 ]
then
    echo "[PASS]: TX failed"
else
    echo "[FAILED]: TX successful but burn-from should be disabled"
fi
echo "[INFO]: Verify token value didn't change"
tokenfactory_wallet1_mint_token=$($CHAIN_BINARY --home $HOME_1 q bank balances $tokenfactory_wallet1_addr -o json | jq -r ".balances[] | select(.denom==\"$tf_token1\") | .amount")
echo "[DEBUG]: expecting: $expected_tokenfactory_wallet1_token"
if [ $tokenfactory_wallet1_mint_token == $expected_tokenfactory_wallet1_token ]
then
    echo "[PASS]: Correct minted tokens in $tokenfactory_wallet1_addr: $tokenfactory_wallet1_mint_token$tf_token1"
else
    echo "[FAILED]: Incorrect minted tokens in $tokenfactory_wallet1_addr expected $expected_tokenfactory_wallet1_token$tf_token1 got $tokenfactory_wallet1_mint_token$tf_token1"
    exit 1
fi
