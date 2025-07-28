
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v7.0.1/interchain-security-cdd-linux
export CONSUMER_CHAIN_BINARY_NAME="sovd"
export CONSUMER_CHAIN_BINARY="./$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=v701-one

export CONSUMER_DOWNTIME_WINDOW="10"
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_DENOM=ucon
export GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=cd-transform
export CONSUMER_ICS="v6.4.0"

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
