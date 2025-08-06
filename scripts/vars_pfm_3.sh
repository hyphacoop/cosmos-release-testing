export validator_count=1

# Chain configuration
export CHAIN_BINARY_NAME="gaiadpfm3"
export CHAIN_BINARY="./$CHAIN_BINARY_NAME"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
export VALOPER_1=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv

export MNEMONIC_RELAYER="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon trouble"
export WALLET_RELAYER=cosmos1jf7j9nvjmnflal5ehaj25p7nsk2t3lkd3tj7zp

export CHAIN_ID=pfm3
export DENOM=uatom
export VAL_FUNDS="10000000000"
export VAL_WHALE="100000000"
export VAL_STAKE="10000000"
export DOWNTIME_WINDOW="10"
export DOWNTIME_JAIL_DURATION="30s"
export EXPEDITED_VOTING_PERIOD="10"
export VOTING_PERIOD="30"
export DEPOSIT_PERIOD="60"
export COMMIT_TIMEOUT="5"
export GAS_PRICE=0.005$DENOM
export GAS=auto
export GAS_ADJUSTMENT=3
export STATE_SYNC_SNAPSHOT_INTERVAL=0
export STATE_SYNC_SNAPSHOT_KEEP_RECENT=5

export COUNT_WIDTH="01"
export moniker_prefix='pfm3_'
export home_prefix='/home/runner/.pfm3_'
export api_prefix="550"
export p2p_prefix="560"
export rpc_prefix="570"
export grpc_prefix="580"
export pprof_prefix="590"
export log_prefix="logpfm3_"

export whale_home=${home_prefix}$COUNT_WIDTH
export whale_api=${api_prefix}$COUNT_WIDTH
export whale_rpc=${rpc_prefix}$COUNT_WIDTH
export whale_log=${log_prefix}$COUNT_WIDTH

export START_SCRIPT="start-pfm3.sh"
export STOP_SCRIPT="stop-pfm3.sh"
export RESET_SCRIPT="reset-pfm3.sh"