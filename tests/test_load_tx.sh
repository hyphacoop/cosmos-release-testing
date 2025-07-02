#!/bin/bash

while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-host)
            RPC_HOST="$2"
            shift
            shift
            ;;
        --rpc-port)
            RPC_PORT="$2"
            shift
            shift
            ;;
        --from-wallet)
            FROM_WALLET="$2"
            shift
            shift
            ;;
        --to-wallet)
            TO_WALLET="$2"
            shift
            shift
            ;;
        --liquid-transfer-to)
            LIQUID_TRANSFER_TO="$2"
            shift
            shift
            ;;
        --valoper_address_1)
            VALOPER_ADDRESS_1="$2"
            shift
            shift
            ;;
        --home)
            HOME_DIR="$2"
            shift
            shift
            ;;
        *)
            echo "unknown arguement: $2"
            shift
            shift
            exit 1
            ;;
    esac
done

echo "[DEBUG]: TX bank send"
echo "$CHAIN_BINARY tx bank send $FROM_WALLET $TO_WALLET $VAL_STAKE_STEP$DENOM --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json"
txhash=$($CHAIN_BINARY tx bank send $FROM_WALLET $TO_WALLET $VAL_STAKE_STEP$DENOM --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json | jq '.txhash' | tr -d '"')
echo "[INFO]: txhash: $txhash"
tests/test_block_production.sh $RPC_HOST $RPC_PORT 5 20
code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: TX delegate funds"
echo "$CHAIN_BINARY tx staking delegate $VALOPER_ADDRESS_1 $VAL_STAKE$DENOM --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json"
txhash=$($CHAIN_BINARY tx staking delegate $VALOPER_ADDRESS_1 $VAL_STAKE$DENOM --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json | jq '.txhash' | tr -d '"')
echo "[INFO]: txhash: $txhash"
tests/test_block_production.sh $RPC_HOST $RPC_PORT 5 20
code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: TX delegate withdraw-rewards"
echo "$CHAIN_BINARY tx distribution withdraw-rewards $VALOPER_ADDRESS_1 --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json"
txhash=$($CHAIN_BINARY tx distribution withdraw-rewards $VALOPER_ADDRESS_1 --home $HOME_DIR --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json | jq '.txhash' | tr -d '"')
echo "[INFO]: txhash: $txhash"
tests/test_block_production.sh $RPC_HOST $RPC_PORT 5 20
code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: TX liquid tokenize-share 1"
echo "$CHAIN_BINARY tx liquid tokenize-share $VALOPER_ADDRESS_1 --home $HOME_DIR 1000000uatom $FROM_WALLET --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM --chain-id $CHAIN_ID -y -o json"
txhash=$($CHAIN_BINARY tx liquid tokenize-share $VALOPER_ADDRESS_1 --home $HOME_DIR 1000000uatom $FROM_WALLET --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM --chain-id $CHAIN_ID -y -o json | jq '.txhash' | tr -d '"')
echo "[INFO]: txhash: $txhash"
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 20
code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: TX liquid tokenize-share 2"
echo "$CHAIN_BINARY tx liquid tokenize-share $VALOPER_ADDRESS_1 --home $HOME_DIR 2000000uatom $FROM_WALLET --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM --chain-id $CHAIN_ID -y -o json"
txhash=$($CHAIN_BINARY tx liquid tokenize-share $VALOPER_ADDRESS_1 --home $HOME_DIR 2000000uatom $FROM_WALLET --from $FROM_WALLET --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES$DENOM --chain-id $CHAIN_ID -y -o json | jq '.txhash' | tr -d '"')
echo "[INFO]: txhash: $txhash"
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 20
code=$($CHAIN_BINARY q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: Query bank balances"
$CHAIN_BINARY --home $HOME_DIR q bank balances $FROM_WALLET

echo "[DEBUG]: Get liquid denom with 1000000uatom"
LIQUID_DENOM1=$($CHAIN_BINARY --home $HOME_DIR q bank balances $FROM_WALLET -o json | jq -r '.balances[] | select(.amount == "1000000") | .denom')
echo "$LIQUID_DENOM1"

echo "[DEBUG]: Get liquid denom with 2000000uatom"
LIQUID_DENOM2=$($CHAIN_BINARY --home $HOME_DIR q bank balances $FROM_WALLET -o json | jq -r '.balances[] | select(.amount == "2000000") | .denom')
echo "$LIQUID_DENOM2"

echo "[DEBUG]: Get record for the 1000000uatom liquid denom"
json=$($CHAIN_BINARY --home $HOME_DIR q liquid tokenize-share-record-by-denom $LIQUID_DENOM1 -o json | jq -r '.')
LIQUID_DENOM1_RECORD_ID=$(echo $json | jq -r ".record.id")
LIQUID_DENOM1_RECORD_OWNER=$(echo $json | jq -r ".record.owner")
LIQUID_DENOM1_RECORD_MODULE_ACCOUNT=$(echo $json | jq -r ".record.module_account")
LIQUID_DENOM1_RECORD_VALIDATOR=$(echo $json | jq -r ".record.validator")
echo "record_id: $LIQUID_DENOM1_RECORD_ID"
echo "record_owner: $LIQUID_DENOM1_RECORD_OWNER"
echo "record_module_account: $LIQUID_DENOM1_RECORD_MODULE_ACCOUNT"
echo "record_validator: $LIQUID_DENOM1_RECORD_VALIDATOR"

echo "[DEBUG]: Get record for the 2000000uatom liquid denom"
json=$($CHAIN_BINARY --home $HOME_DIR q liquid tokenize-share-record-by-denom $LIQUID_DENOM2 -o json | jq -r '.')
LIQUID_DENOM2_RECORD_ID=$(echo $json | jq -r ".record.id")
LIQUID_DENOM2_RECORD_OWNER=$(echo $json | jq -r ".record.owner")
LIQUID_DENOM2_RECORD_MODULE_ACCOUNT=$(echo $json | jq -r ".record.module_account")
LIQUID_DENOM2_RECORD_VALIDATOR=$(echo $json | jq -r ".record.validator")
echo "record_id: $LIQUID_DENOM2_RECORD_ID"
echo "record_owner: $LIQUID_DENOM2_RECORD_OWNER"
echo "record_module_account: $LIQUID_DENOM2_RECORD_MODULE_ACCOUNT"
echo "record_validator: $LIQUID_DENOM2_RECORD_VALIDATOR"

echo "[DEBUG]: Transfer tokenized share ownership"
echo "$CHAIN_BINARY --home $HOME_DIR tx liquid transfer-tokenize-share-record $LIQUID_DENOM1_RECORD_ID $LIQUID_TRANSFER_TO --from $FROM_WALLET --gas auto --gas-adjustment 3 --gas-prices 0.005uatom -y -o json"
txhash=$($CHAIN_BINARY --home $HOME_DIR tx liquid transfer-tokenize-share-record $LIQUID_DENOM1_RECORD_ID $LIQUID_TRANSFER_TO --from $FROM_WALLET --gas auto --gas-adjustment 3 --gas-prices 0.005uatom -y -o json | jq '.txhash' | tr -d '"')
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 20
code=$($CHAIN_BINARY --home $HOME_DIR q tx $txhash -o json --home $HOME_DIR | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi

echo "[DEBUG]: Redeem tokenized shares"
echo "$CHAIN_BINARY --home $HOME_DIR tx liquid redeem-tokens 2000000$LIQUID_DENOM2 --from $FROM_WALLET --gas auto --gas-adjustment 3 --gas-prices 0.005uatom -y -o json"
txhash=$($CHAIN_BINARY --home $HOME_DIR tx liquid redeem-tokens 2000000$LIQUID_DENOM2 --from $FROM_WALLET --gas auto --gas-adjustment 3 --gas-prices 0.005uatom -y-o json | jq '.txhash' | tr -d '"')
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 20
code=$($CHAIN_BINARY --home $HOME_DIR q tx $txhash -o json --home $HOME_1 | jq '.code')
echo "[INFO]: Code is: $code"
if [ -z $code ]; then
    echo "[ERROR]: code returned blank, TX was unsuccessful."
    exit 1
elif [ $code -ne 0 ]; then
    echo "[ERROR]: code returned: $code, TX unsuccessful"
    exit 1
fi
