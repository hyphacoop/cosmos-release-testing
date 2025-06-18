export validator_count=5

# Chain configuration
export CHAIN_BINARY_NAME="gaiad"
export CHAIN_BINARY="./$CHAIN_BINARY_NAME"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
export VALOPER_1=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv

export MNEMONIC_RELAYER="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon trouble"
export WALLET_RELAYER=cosmos1jf7j9nvjmnflal5ehaj25p7nsk2t3lkd3tj7zp

export CHAIN_ID=testnet
export DENOM=uatom
export VAL_FUNDS="10000000000"
export VAL_WHALE="100000000"
export VAL_STAKE="10000000"
export DOWNTIME_WINDOW="10"
export EXPEDITED_VOTING_PERIOD="10"
export VOTING_PERIOD="30"
export DEPOSIT_PERIOD="60"
export COMMIT_TIMEOUT="5"
export GAS_PRICE=0.005$DENOM
export GAS=auto
export GAS_ADJUSTMENT=3
export STATE_SYNC_SNAPSHOT_INTERVAL=50
export STATE_SYNC_SNAPSHOT_KEEP_RECENT=5

export moniker_prefix='val_'
export home_prefix='/home/runner/.val_'
export api_prefix="250"
export p2p_prefix="260"
export rpc_prefix="270"
export grpc_prefix="280"
export pprof_prefix="290"
export sign_prefix="240"
export log_prefix="log_"

export whale_home=${home_prefix}01
export whale_rpc=${rpc_prefix}01

export START_SCRIPT="start.sh"
export STOP_SCRIPT="stop.sh"
export RESET_SCRIPT="reset.sh"