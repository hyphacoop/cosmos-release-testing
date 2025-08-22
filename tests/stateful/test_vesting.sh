#!/bin/bash
set -e

vesting_time="5 minutes"
vesting_amount=1003000000
vesting_stake_amount=40000000000

# Create a vesting account with $vesting_amount atom
echo "[INFO]: > Testing vesting account with $vesting_time..."
vesting_wallet1_json=$($CHAIN_BINARY --home $HOME_1 keys add vesting-1 --output json)
echo "[INFO]: vesting_wallet1: $vesting_wallet1_json"
vesting_wallet1_addr=$(echo $vesting_wallet1_json | jq -r '.address')

echo "[INFO]: Creating vesting wallet: $vesting_wallet1_addr"
vesting_end_time=$(date -d "+$vesting_time" +%s)
echo "[INFO]: Vesting end time: $vesting_end_time"
$CHAIN_BINARY --home $HOME_1 tx vesting create-vesting-account $vesting_wallet1_addr $vesting_amount$DENOM $vesting_end_time --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Wait until spendable balance matches vesting amount"
current_block=$(curl -s 127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
count=0
current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
echo "[INFO]: Current spendable balance: $current_spend_amount"

until [ $current_spend_amount -eq $vesting_amount ]
do
    current_block=$(curl -s http://127.0.0.1:$VAL1_RPC_PORT/block | jq -r .result.block.header.height)
    if [ "$echo_height" != "$current_block" ]
    then
        echo "[INFO] Current height: $current_block"
        current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
        echo "[INFO]: Current spendable balance: $current_spend_amount"
        echo_height=$current_block
        count=0
    fi
    let count=$count+1
    if [ $count -gt 20 ]
    then
        echo "[ERROR]: chain stopped at height: $current_block"
        exit 1
    fi
    sleep 1
done

block_timestamp=$($CHAIN_BINARY --home $HOME_1 q block --type=height $current_block -o json | jq -r '.header.time')
echo "Last block timestamp: $block_timestamp"
block_unix_time=$(date -d "$block_timestamp" +%s)
echo "Last block UNIX time: $block_unix_time"

# check block time matches vesting period
let vesting_end_time_delta=$vesting_end_time+7
if [ $block_unix_time -lt $vesting_end_time_delta ] && [ $block_unix_time -ge $vesting_end_time ]
then
    echo "Spendable balance matches vesting end time"
else
    echo "Spendable balance does not match end time"
    exit 1
fi

# test sending all spendable balances back
echo "[INFO]: Send all spendable uatom back to $WALLET_1"
let bank_send_amount=$current_spend_amount-29000
tx_json=$($CHAIN_BINARY --home $HOME_1 tx bank send $vesting_wallet1_addr $WALLET_1 $bank_send_amount$DENOM --from $vesting_wallet1_addr --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y -o json)
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
vw1_send_txhash=$(echo $tx_json | jq -r '.txhash' | tr -d '"')
echo "[INFO]: tx result:"
$CHAIN_BINARY --home $HOME_1 q tx $vw1_send_txhash
echo "[INFO]: Current spendable balance after tx"
$CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr
current_spend_amount=$($CHAIN_BINARY --home $HOME_1 q bank spendable-balances $vesting_wallet1_addr -o json | jq -r '.balances[] | select(.denom="uatom") | .amount')
if [ ! -z $current_spend_amount ]
then
    echo "[ERROR]: Spendable amount is not empty"
    exit 1
else
    echo "[INFO]: Spendable amount have been sent back"
fi

# Create a permanently locked vesting account with 100 atom
echo "[INFO]: > Testing permanent locked vesting account..."
vesting_wallet2_json=$($CHAIN_BINARY --home $HOME_1 keys add vesting-2 --output json)
echo "[INFO]: vesting_wallet2: $vesting_wallet2_json"
vesting_wallet2_addr=$(echo $vesting_wallet2_json | jq -r '.address')

echo "[INFO]: create-permanent-locked-account wallet: $vesting_wallet2_addr"
$CHAIN_BINARY --home $HOME_1 tx vesting create-permanent-locked-account $vesting_wallet2_addr $vesting_stake_amount$DENOM --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Send liquid tokens for gas"
$CHAIN_BINARY --home $HOME_1 tx bank send $WALLET_1 $vesting_wallet2_addr 1000000$DENOM --from $MONIKER_1 --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM -y
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10

echo "[INFO]: Delegating $vesting_stake_amount$DENOM to $VALOPER_1"
delgate_json=$($CHAIN_BINARY tx staking delegate $VALOPER_1 $vesting_stake_amount$DENOM --home $HOME_1 --from vesting-2 --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json -b sync)
echo "[INFO]: Delegation TX output:"
echo "$delgate_json" | jq -r "."
delgate_txhash=$(echo $delgate_json | jq -r '.txhash' | tr -d '"')
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 1 10
echo "[INFO]: TX info:"
$CHAIN_BINARY --home $HOME_1 q tx $delgate_txhash

echo "[INFO]: Waiting for rewards to accumulate"
sleep 600
echo "[INFO]: Current distribution rewards:"
$CHAIN_BINARY --home $HOME_1 q distribution rewards $vesting_wallet2_addr
echo "[INFO]: Withdrawing rewards for test account..."
starting_spendable_balance=$($CHAIN_BINARY q bank spendable-balances $vesting_wallet2_addr --home $HOME_1 -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
starting_balance=$($CHAIN_BINARY q bank balances $vesting_wallet2_addr --home $HOME_1 -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
echo "[INFO]: Starting bank spendable balance: $starting_spendable_balance"
echo "[INFO]: Starting bank balance: $starting_balance"
pending_reward=$(gaiad q distribution rewards $vesting_wallet2_addr -o json | jq -r ".rewards[] | select(.validator_address=\"$VALOPER_1\") | .reward[]")
echo "[INFO]: Current pending reward: $pending_reward"
txhash=$($CHAIN_BINARY tx distribution withdraw-rewards $VALOPER_1 --home $HOME_1 --from vesting-2 --keyring-backend test --gas $GAS --gas-adjustment $GAS_ADJUSTMENT --fees $BASE_FEES$DENOM --chain-id $CHAIN_ID -y -o json -b sync | jq '.txhash' | tr -d '"')
# wait for 1 block
tests/test_block_production.sh 127.0.0.1 $VAL1_RPC_PORT 5 10
echo "[INFO]: withdraw-rewards TX:"
$CHAIN_BINARY --home $HOME_1 q tx $txhash

# Check the funds again
echo "[INFO]: Spendable-balances:"
echo $($CHAIN_BINARY q bank spendable-balances $vesting_wallet2_addr --home $HOME_1 -o json)
ending_spendable_balance=$($CHAIN_BINARY q bank spendable-balances $vesting_wallet2_addr --home $HOME_1 -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
ending_balance=$($CHAIN_BINARY q bank balances $vesting_wallet2_addr --home $HOME_1 -o json | jq -r '.balances[] | select(.denom=="uatom").amount')
echo "[INFO]: Ending bank spendable balance: $ending_spendable_balance"
echo "[INFO]: Ending bank balance: $ending_balance"
delta=$[ $ending_spendable_balance - $starting_spendable_balance]
if [ $delta -gt 0 ]; then
    echo "$delta $DENOM were withdrawn successfully."
else
    echo "Rewards could not be withdrawn. Delta is: $delta"
    exit 1
fi
