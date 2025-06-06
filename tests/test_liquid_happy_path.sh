#!/bin/bash
# set -x
source scripts/process_tx.sh

delegation=100000000
tokenize=50000000
bank_send_amount=20000000
liquid_1_redeem=20000000
tokenized_denom=$VALOPER_1/$VALOPER_TOKENIZATION

#$CHAIN_BINARY keys list --home $HOME_1 --output json

happy_liquid_1=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_liquid_1").address')
happy_liquid_2=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_liquid_2").address')
happy_owner=$($CHAIN_BINARY keys list --home $HOME_1 --output json | jq -r '.[] | select(.name=="happy_owner").address')

echo "** HAPPY PATH> STEP 1: TOKENIZE **"

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

    liquid_shares_pre_tokenize=$($CHAIN_BINARY q liquid liquid-validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.liquid_validator.liquid_shares')
    # Remove the last 18 zeroes
    liquid_shares_pre_tokenize=${liquid_shares_pre_tokenize:0:${#liquid_shares_pre_tokenize}-18}
    echo "Tokenizing shares with $happy_liquid_1..."
    submit_tx "tx liquid tokenize-share $VALOPER_1 $tokenize$DENOM $happy_liquid_1 --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    
    liquid_shares_post_tokenize=$($CHAIN_BINARY q liquid liquid-validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.liquid_validator.liquid_shares')
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

echo "** HAPPY PATH> STEP 2: TRANSFER OWNERSHIP **"

    record_id=$($CHAIN_BINARY q liquid tokenize-share-record-by-denom $liquid_denom --home $HOME_1 -o json | jq -r '.record.id')
    owner=$($CHAIN_BINARY q liquid tokenize-share-record-by-denom $liquid_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "> $owner owns record $record_id."
    echo "> Transferring token ownership record to new_owner."
    submit_tx "tx liquid transfer-tokenize-share-record $record_id $happy_owner --from $owner --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $HOME_1
    owner=$($CHAIN_BINARY q liquid tokenize-share-record-by-denom $liquid_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "$owner owns record $record_id."
    if [[ "$owner" == "$happy_owner" ]]; then
        echo "Token ownership transfer succeeded."
    else
        echo "Token ownership transfer failed."
    fi

    echo "Transferring token ownership record back to happy_liquid_1..."
    submit_tx "tx liquid transfer-tokenize-share-record $record_id $happy_liquid_1 --from $owner --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -o json -y" $CHAIN_BINARY $HOME_1
    owner=$($CHAIN_BINARY q liquid tokenize-share-record-by-denom $liquid_denom --home $HOME_1 -o json | jq -r '.record.owner')
    echo "$owner owns record $record_id."
    if [[ "$owner" == "$happy_liquid_1" ]]; then
        echo "Token ownership transfer succeeded."
    else
        echo "Token ownership transfer failed."
    fi

echo "** HAPPY PATH> STEP 3: TRANSFER TOKENS  **"

    happy_liquid_1_delegations_1=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    echo "happy_liquid_1 delegations: $happy_liquid_1_delegations_1"

    echo "Sending tokens from happy_liquid_1 to happy_liquid_2 via bank send..."
    submit_tx "tx bank send $happy_liquid_1 $happy_liquid_2 $bank_send_amount$liquid_denom --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1

echo "** HAPPY PATH> STEP 4: REDEEM TOKENS **"
    echo "Redeeming tokens from happy_liquid_1..."
    $CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq '.'
    liquid_denom_1=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r '.balances[-2].denom')
    liquid_balance_1=$($CHAIN_BINARY q bank balances $happy_liquid_1 --home $HOME_1 -o json | jq -r '.balances[-2].amount')
    echo "> Liquid denom 1: $liquid_denom"
    echo "> Liquid balance 1: $liquid_balance_1"
    submit_tx "tx liquid redeem-tokens $liquid_balance_1$liquid_denom_1 --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    sleep $(($COMMIT_TIMEOUT*2))
    echo "Redeeming tokens from happy_liquid_2..."
    $CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq '.'
    liquid_denom_2=$($CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq -r '.balances[-2].denom')
    liquid_balance_2=$($CHAIN_BINARY q bank balances $happy_liquid_2 --home $HOME_1 -o json | jq -r '.balances[-2].amount')
    echo "> Liquid denom 2: $liquid_denom_2"
    echo "> Liquid balance 2: $liquid_balance_2"
    submit_tx "tx liquid redeem-tokens $liquid_balance_2$liquid_denom_2 --from $happy_liquid_2 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICE$DENOM -y" $CHAIN_BINARY $HOME_1
    sleep $(($COMMIT_TIMEOUT*2))

    happy_liquid_1_delegations_2=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    happy_liquid_1_delegations_diff=$((${happy_liquid_1_delegations_2%.*}-${happy_liquid_1_delegations_1%.*}))
    happy_liquid_2_delegations=$($CHAIN_BINARY q staking delegations $happy_liquid_2 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    
    happy_liquid_1_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')
    happy_liquid_2_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_2 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')
    happy_liquid_3_delegation_balance=$($CHAIN_BINARY q staking delegations $happy_liquid_3 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).balance.amount')

    echo "happy_liquid_1 delegation shares: ${happy_liquid_1_delegations_2%.*}"
    echo "happy_liquid_1 delegation shares increase: $happy_liquid_1_delegations_diff"

    echo "happy_liquid_1 delegation balance: $happy_liquid_1_delegation_balance"
    echo "happy_liquid_2 delegation shares: ${happy_liquid_2_delegations%.*}"
    
echo "** HAPPY PATH> CLEANUP **"

    echo "Validator unbond from happy_liquid_1..."
    submit_tx "tx staking unbond $VALOPER_1 $happy_liquid_1_delegations_2$DENOM --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1

    echo "Validator unbond from happy_liquid_2..."
    submit_tx "tx staking unbond $VALOPER_1 $happy_liquid_2_delegations$DENOM --from $happy_liquid_2 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1

    happy_liquid_1_delegations=$($CHAIN_BINARY q staking delegations $happy_liquid_1 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    happy_liquid_2_delegations=$($CHAIN_BINARY q staking delegations $happy_liquid_2 --home $HOME_1 -o json | jq -r --arg ADDRESS "$VALOPER_1" '.delegation_responses[] | select(.delegation.validator_address==$ADDRESS).delegation.shares')
    echo "happy_liquid_1 delegation shares: ${happy_liquid_1_delegations%.*}"
    echo "happy_liquid_2 delegation shares: ${happy_liquid_2_delegations%.*}"