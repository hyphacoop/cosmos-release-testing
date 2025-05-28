export validator_count=5

# Chain configuration
export CHAIN_BINARY_NAME="gaiad"
export CHAIN_BINARY="./$CHAIN_BINARY_NAME"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
export VALOPER_1=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv
export CHAIN_ID=testnet
export DENOM=uatom
export VAL_FUNDS="10000000000"
export VAL_WHALE="100000000"
export VAL_STAKE="10000000"
export DOWNTIME_WINDOW="10"
export EXPEDITED_VOTING_PERIOD="10"
export VOTING_PERIOD="30"
export DEPOSIT_PERIOD="60"
export TIMEOUT_COMMIT="5"
export GAS_PRICE=0.005$DENOM
export GAS=auto
export GAS_ADJUSTMENT=3

export moniker_prefix='val_'
export home_prefix='/home/runner/.val_'
export whale_home=${home_prefix}001
export api_prefix="25"
export p2p_prefix="26"
export rpc_prefix="27"
export grpc_prefix="28"
export pprof_prefix="29"
export log_prefix="log_"