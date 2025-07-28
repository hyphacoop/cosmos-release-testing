
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v7.0.1/interchain-security-cdd-linux
export CONSUMER_CHAIN_BINARY_NAME="sovd"
export CONSUMER_CHAIN_BINARY="./$CONSUMER_CHAIN_BINARY_NAME"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc

export MNEMONIC_RELAYER="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon trouble"
export WALLET_RELAYER=consumer1jf7j9nvjmnflal5ehaj25p7nsk2t3lkd57l33x

export CONSUMER_CHAIN_ID=v701-one
export CONSUMER_DENOM=ucon
export CONSUMER_DOWNTIME_WINDOW="10"
export GAS_PRICE=0.005$CONSUMER_DENOM
export GAS_ADJUSTMENT=3

export consumer_moniker_prefix='sov_'
export consumer_home_prefix='/home/runner/.sov_'
export consumer_api_prefix="171"
export consumer_p2p_prefix="172"
export consumer_rpc_prefix="173"
export consumer_grpc_prefix="174"
export consumer_pprof_prefix="175"
export consumer_log_prefix="sov_"

export consumer_whale_home=${home_prefix}$COUNT_WIDTH
export consumer_whale_api=${api_prefix}$COUNT_WIDTH
export consumer_whale_rpc=${rpc_prefix}$COUNT_WIDTH
export consumer_whale_log=${log_prefix}$COUNT_WIDTH

export START_SCRIPT="start-sov.sh"
export STOP_SCRIPT="stop-sov.sh"
export RESET_SCRIPT="reset-sov.sh"
