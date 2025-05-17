#!/bin/bash
# set -x
source scripts/process_tx.sh

delegation=100000000
tokenize=50000000
bank_send_amount=20000000
ibc_transfer_amount=10000000
liquid_1_redeem=20000000
tokenized_denom=$VALOPER_1/$VALOPER_TOKENIZATION

#$CHAIN_BINARY keys list --home $HOME_1 --output json

happy_liquid_1=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_liquid_1").address')
happy_liquid_2=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_liquid_2").address')
# appy_liquid_3=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_liquid_3").address')
# happy_owner=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_owner").address')

echo "** HAPPY PATH> STEP 1: VALIDATOR BOND **"

    # delegator_shares_1=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.delegator_shares')
    validator_bond_shares_1=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.validator_bond_shares')
    # echo "> Delegating with happy_bonding."
    # echo "> Delegator shares 1: $delegator_shares_1"
    # submit_tx "tx staking delegate $VALOPER_1 $delegation$DENOM --from $happy_bonding -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy post-delegate-1 $happy_bonding $delegation
    # $CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1

    # delegator_shares_2=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.delegator_shares')
    # echo "Delegator shares 2: $delegator_shares_2"
    
    # shares_diff=$((${delegator_shares_2%.*}-${delegator_shares_1%.*})) # remove decimal portion
    # echo "Delegator shares difference: $shares_diff"
    # echo "Delegation: $delegation"
    # if [[ $shares_diff -ne $delegation ]]; then
    #     echo "Delegation unsuccessful."
    #     exit 1
    # fi

    echo "> Validator bond with val1."
    # $CHAIN_BINARY q staking validator cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv --home $HOME_1
    submit_tx "tx staking validator-bond $VALOPER_1 --from $WALLET_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
    # $CHAIN_BINARY q staking validator cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv --home $HOME_1

    validator_bond_shares_2=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.validator_bond_shares')
    echo "> Validator bond shares 1: $validator_bond_shares_1"
    echo "> Validator bond shares 2: $validator_bond_shares_2"
    bond_shares_diff=$(echo "$validator_bond_shares_2-$validator_bond_shares_1" | bc -l)
    # bond_shares_diff=$((${validator_bond_shares_2%.*}-${validator_bond_shares_1%.*})) # remove decimal portion
    echo "Bond shares difference: $bond_shares_diff"
    # echo "Delegation: $delegation"
    # if [[ $shares_diff -ne $delegation  ]]; then
    #     echo "Validator bond unsuccessful."
    #     exit 1
    # fi

echo "** HAPPY PATH> STEP 2: TOKENIZE **"

    delegator_shares_1=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.delegator_shares')
    echo "> Delegator shares 1: $delegator_shares_1"
    echo "> Delegating with $happy_liquid_1."
    submit_tx "tx staking delegate $VALOPER_1 $delegation$DENOM --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    delegator_shares_2=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.delegator_shares')
    echo "> Delegator shares 2: $delegator_shares_2"
    shares_diff=$((${delegator_shares_2%.*}-${delegator_shares_1%.*})) # remove decimal portion
    echo "Delegator shares difference: $shares_diff"
    echo "Delegation: $delegation"
    if [[ $shares_diff -ne $delegation ]]; then
        echo "Delegation unsuccessful."
        exit 1
    fi

    liquid_shares_pre_tokenize=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.liquid_shares')
    # Remove the last 18 zeroes
    liquid_shares_pre_tokenize=${liquid_shares_pre_tokenize:0:${#liquid_shares_pre_tokenize}-18}
    echo "Tokenizing shares with $happy_liquid_1..."
    submit_tx "tx staking tokenize-share $VALOPER_1 $tokenize$DENOM $happy_liquid_1 --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    
    liquid_shares_post_tokenize=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator.liquid_shares')
    # Remove the last 18 zeroes
    liquid_shares_post_tokenize=${liquid_shares_post_tokenize:0:${#liquid_shares_post_tokenize}-18}
    echo "> Liquid shares post-tokenize: $liquid_shares_post_tokenize"
    echo "> Liquid shares pre-tokenize: $liquid_shares_pre_tokenize"
    liquid_shares_diff=$(echo "$liquid_shares_post_tokenize-$liquid_shares_pre_tokenize" | bc -l)
    echo "> Liquid shares difference: $liquid_shares_diff"
    liquid_shares_diff=${liquid_shares_diff%.*}
    echo "> Liquid shares difference: $liquid_shares_diff"
    echo "> Tokenize amount: $tokenize"
    if [[ $liquid_shares_diff -eq $tokenize  ]]; then
        echo "Tokenization successful."
    elif [[ $(($liquid_shares_diff-$tokenize)) -eq 1 ]]; then
        echo "Tokenization successful: liquid shares increase off by 1"
    elif [[ $(($tokenize-$liquid_shares_diff)) -eq 1 ]]; then
        echo "Tokenization successful: liquid shares increase off by 1"
    else
        echo "Tokenization unsuccessful: unexpected increase in liquid shares amount ($liquid_shares_diff != $tokenize)"
        exit 1 
    fi

    $CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1
    liquid_denom=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r '.balances[-2].denom')
    liquid_balance=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg DENOM "$liquid_denom" '.balances[] | select(.denom==$DENOM).amount')
    echo "Liquid balance: ${liquid_balance%.*}"
    if [[ ${liquid_balance%.*} -ne $tokenize ]]; then
        echo "Tokenize unsuccessful: unexpected liquid token balance"
        exit 1
    fi

echo "** HAPPY PATH> STEP 3: TRANSFER OWNERSHIP **"

    record_id=$($CHAIN_BINARY q staking tokenize-share-record-by-denom $tokenized_denom --home $HOME_1 -o json | jq -r '.record.id')
    owner=$($CHAIN_BINARY q staking tokenize-share-record-by-denom $tokenized_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "> $owner owns record $record_id."
    echo "Transferring token ownership record to new_owner..."
    submit_tx "tx staking transfer-tokenize-share-record $record_id $happy_owner --from $owner --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $HOME_1
    owner=$($CHAIN_BINARY q staking tokenize-share-record-by-denom $tokenized_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "$owner owns record $record_id."
    if [[ "$owner" == "$happy_owner" ]]; then
        echo "Token ownership transfer succeeded."
    else
        echo "Token ownership transfer failed."
    fi

    echo "Transferring token ownership record back to happy_liquid_1..."
    submit_tx "tx staking transfer-tokenize-share-record $record_id $happy_liquid_1 --from $owner --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $HOME_1
    owner=$($CHAIN_BINARY q staking tokenize-share-record-by-denom $tokenized_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "$owner owns record $record_id."
    if [[ "$owner" == "$happy_liquid_1" ]]; then
        echo "Token ownership transfer succeeded."
    else
        echo "Token ownership transfer failed."
    fi

echo "** HAPPY PATH> STEP 4: TRANSFER TOKENS  **"

    happy_liquid_1_delegations_1=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    echo "happy_liquid_1 delegations: $happy_liquid_1_delegations_1"

    echo "Sending tokens from happy_liquid_1 to happy_liquid_2 via bank send..."
    submit_tx "tx bank send $happy_liquid_1 $happy_liquid_2 $bank_send_amount$tokenized_denom --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1

echo "** HAPPY PATH> STEP 5: REDEEM TOKENS **"
    echo "Redeeming tokens from happy_liquid_1..."
    $CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq '.'
    liquid_denom_1=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r '.balances[-2].denom')
    liquid_balance_1=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r '.balances[-2].amount')
    echo "> Liquid denom 1: $liquid_denom"
    echo "> Liquid balance 1: $liquid_balance_1"
    submit_tx "tx staking redeem-tokens $liquid_balance_1$liquid_denom_1 --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    sleep $(($COMMIT_TIMEOUT*2))
    echo "Redeeming tokens from happy_liquid_2..."
    $CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq '.'
    liquid_denom_2=$($CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq -r '.balances[-2].denom')
    liquid_balance_2=$($CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq -r '.balances[-2].amount')
    echo "> Liquid denom 2: $liquid_denom_2"
    echo "> Liquid balance 2: $liquid_balance_2"
    submit_tx "tx staking redeem-tokens $liquid_balance_2$liquid_denom_2 --from $happy_liquid_2 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    sleep $(($COMMIT_TIMEOUT*2))

    # echo "Sending $ibc_denom tokens from STRIDE_WALLET_LIQUID to $CHAIN_ID chain for redeem operation..."
    # $CHAIN_BINARY q bank balances $happy_liquid_3 --home $HOME_1
    # submit_ibc_tx "tx ibc-transfer transfer transfer channel-1 $happy_liquid_3 $ibc_transfer_amount$ibc_denom --from $STRIDE_WALLET_LIQUID -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$STRIDE_DENOM -y" $STRIDE_CHAIN_BINARY $STRIDE_HOME_1
    # sleep 20
    # $CHAIN_BINARY q bank balances $happy_liquid_3 --home $HOME_1
    # echo "***RELAYER DATA***"
    # journalctl -u $RELAYER | tail -n 100
    # echo "***RELAYER DATA***"
    # echo "Redeeming tokens from happy_liquid_3..."
    # $CHAIN_BINARY q tendermint-validator-set --home $HOME_1
    # $CHAIN_BINARY q tendermint-validator-set --home $STRIDE_HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy pre-redeem-3 $happy_liquid_3 $ibc_transfer_amount
    # submit_tx "tx staking redeem-tokens $ibc_transfer_amount$tokenized_denom --from $happy_liquid_3 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy post-redeem-3 $happy_liquid_3 $ibc_transfer_amount

    happy_liquid_1_delegations_2=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    happy_liquid_1_delegations_diff=$((${happy_liquid_1_delegations_2%.*}-${happy_liquid_1_delegations_1%.*}))
    happy_liquid_2_delegations=$($CHAIN_BINARY q staking delegations $happy_liquid_2 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    # happy_liquid_3_delegations=$($CHAIN_BINARY q staking delegations $happy_liquid_3 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')

    happy_liquid_1_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')
    happy_liquid_2_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_2 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')
    happy_liquid_3_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_3 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')

    echo "happy_liquid_1 delegation shares: ${happy_liquid_1_delegations_2%.*}"
    echo "happy_liquid_1 delegation shares increase: $happy_liquid_1_delegations_diff"
    # if [[ $happy_liquid_1_delegations_diff -ne 20000000 ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation shares for happy_liquid_1"
    #     exit 1
    # fi

    echo "happy_liquid_1 delegation balance: $happy_liquid_1_delegation_balance"
    # if [[ $happy_liquid_1_delegation_balance -ne 70000000 ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation balance for happy_liquid_1"
    #     exit 1
    # fi

    echo "happy_liquid_2 delegation shares: ${happy_liquid_2_delegations%.*}"
    # if [[ ${happy_liquid_2_delegations%.*} -ne $bank_send_amount ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation shares for happy_liquid_2"
    #     exit 1
    # fi

    # echo "happy_liquid_2 delegation balance: $happy_liquid_2_delegation_balance"
    # if [[ $happy_liquid_2_delegation_balance -ne $bank_send_amount ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation balance for happy_liquid_2"
    #     exit 1
    # fi

    # echo "happy_liquid_3 delegation shares: ${happy_liquid_3_delegations%.*}"
    # if [[ ${happy_liquid_3_delegations%.*} -ne $ibc_transfer_amount ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation shares for happy_liquid_3"
    #     exit 1
    # fi

    # echo "happy_liquid_3 delegation balance: $happy_liquid_2_delegation_balance"
    # if [[ $happy_liquid_3_delegation_balance -ne $ibc_transfer_amount ]]; then
    #     echo "Redeem unsuccessful: unexpected delegation balance for happy_liquid_3"
    #     exit 1
    # fi

echo "** HAPPY PATH> CLEANUP **"

    echo "Validator unbond from Val1"
    # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-1 $happy_bonding $delegation
    submit_tx "tx staking validator-unbond $VALOPER_1 --from $WALLET_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
    # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-1 $happy_bonding $delegation

    validator_bond_shares=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator_bond_shares')
    echo "Validator bond shares: ${validator_bond_shares%.*}"
    if [[ ${validator_bond_shares%.*} -ne 0  ]]; then
        echo "Unbond unsuccessful: unexpected validator bond shares amount"
        exit 1
    fi

    echo "Validator unbond from happy_liquid_1..."
    # # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-2 $happy_liquid_1 $happy_liquid_1_delegation_balance
    submit_tx "tx staking unbond $VALOPER_1 $happy_liquid_1_delegations_2$DENOM --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-2 $happy_liquid_1 70000000

    echo "Validator unbond from happy_liquid_2..."
    # # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-3 $happy_liquid_2 $bank_send_amount
    submit_tx "tx staking unbond $VALOPER_1 $happy_liquid_2_delegations$DENOM --from $happy_liquid_2 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-3 $happy_liquid_2 $bank_send_amount

    # echo "Validator unbond from happy_liquid_3..."
    # # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-4 $happy_liquid_3 $ibc_transfer_amount
    # submit_tx "tx staking unbond $VALOPER_1 $ibc_transfer_amount$DENOM --from $happy_liquid_3 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
    # # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-4 $happy_liquid_3 $ibc_transfer_amount
