#!/bin/bash
set -e

mint_token=1000000000000000
bank_send=2000000000$DENOM
tf_denom_name="cake"
tf_metadata_description="Tokens for cake"
tf_bank_send=10000
tf_burn_amount=1000

# Get gov address
gov_address=$($CHAIN_BINARY --home $HOME_1 q auth module-account gov -o json | jq -r '.account.value.address')
echo "[INFO]: Gov addressis : $gov_address" 

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

# Test disabled burn-from tx
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

# Test disabled force-transfer tx
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

# Test setting denom metadata
echo "[INFO]: > Test denom-metadata"
denom_metadata=$($CHAIN_BINARY --home $HOME_1 q bank denom-metadata $tf_token1 -o json | jq -r '.')
echo "[INFO]: Current meta for $tf_token1"
echo "$denom_metadata"

$CHAIN_BINARY --home $HOME_1 tx tokenfactory modify-metadata $tf_token1 $tf_denom_name "$tf_metadata_description" 6 --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
denom_metadata=$($CHAIN_BINARY --home $HOME_1 q bank denom-metadata $tf_token1 -o json | jq -r '.')

echo "[INFO]: Current meta for $tf_token1"
echo "$denom_metadata"

echo "[INFO]: Verify metadata"
denom_description_query=$(echo $denom_metadata | jq -r '.metadata.description')
echo "[DEBUG]: metadata from query: $denom_description_query"
if [ "$denom_description_query" == "$tf_metadata_description" ]
then
    echo "[PASS]: Description matches"
else
    echo "[ERROR]: Description does not match. Expected: $tf_metadata_description got $denom_description_query"
    exit 1
fi

# Test changing token to new owner
echo "[INFO]: > Test change token to new owner (to gov address)"
current_tf_token1_admin=$($CHAIN_BINARY --home $HOME_1 q tokenfactory denom-authority-metadata $tf_token1 -o json | jq -r '.authority_metadata.admin')
echo "[INFO]: Current admin for token $tf_token1: $current_tf_token1_admin"

echo "[DEBUG]: Submitting chain-admin tx"
$CHAIN_BINARY --home $HOME_1 tx tokenfactory change-admin $tf_token1 $gov_address --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

current_tf_token1_admin=$($CHAIN_BINARY --home $HOME_1 q tokenfactory denom-authority-metadata $tf_token1 -o json | jq -r '.authority_metadata.admin')
echo "[INFO]: Current admin for token $tf_token1: $current_tf_token1_admin"

if [ "$current_tf_token1_admin" == "$gov_address" ]
then
    echo "[PASS]: Token admin changed"
else
    echo "[ERROR]: Token admin does not match. Expected: $gov_address got $current_tf_token1_admin"
    exit 1
fi

# Test disabled burn token
echo "[INFO]: > Test disabled MsgBurn proposal"
jq -r --arg SENDER $gov_address '.messages[0].sender |= $SENDER' templates/proposal-tokenfactory-burn-token.json > proposal-tokenfactory-burn-token_sender.json
jq -r --arg BURN $tf_burn_amount '.messages[0].amount.amount |= $BURN' proposal-tokenfactory-burn-token_sender.json > proposal-tokenfactory-burn-token_burn.json
jq -r --arg BURN $tf_token1 '.messages[0].amount.denom |= $DENOM' proposal-tokenfactory-burn-token_burn.json > proposal-tokenfactory-burn-token_denom.json
jq -r --arg BURNFROM $tokenfactory_wallet1_json '.messages[0].burnFromAddress |= $BURNFROM' proposal-tokenfactory-burn-token_denom.json > proposal-tokenfactory-burn-token.json
echo "[DEBUG]: Proposal file:"
cat proposal-tokenfactory-burn-token.json | jq -r '.'

echo "[Debug]: Submitting proposal..."
source scripts/submit_proposal.sh proposal-tokenfactory-burn-token.json yes

echo $VOTE_TX_JSON
