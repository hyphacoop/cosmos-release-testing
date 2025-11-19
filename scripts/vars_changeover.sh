
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v6.4.0/interchain-security-cdd-linux
export CONSUMER_CHAIN_BINARY_NAME="sovd"
export CONSUMER_CHAIN_BINARY="./$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID="v640-one"

export CONSUMER_DOWNTIME_WINDOW="10"
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_DENOM=ucon
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=cd-transform
export CONSUMER_ICS="v6.4.0"

export consumer_moniker_prefix='sov_'
export consumer_home_prefix='/home/runner/.sov_'
export consumer_api_prefix="641"
export consumer_p2p_prefix="642"
export consumer_rpc_prefix="643"
export consumer_grpc_prefix="644"
export consumer_pprof_prefix="645"
export consumer_log_prefix="sov_"

export consumer_whale_home=${consumer_home_prefix}$COUNT_WIDTH
export consumer_whale_api=${consumer_api_prefix}$COUNT_WIDTH
export consumer_whale_rpc=${consumer_rpc_prefix}$COUNT_WIDTH
export consumer_whale_log=${consumer_log_prefix}$COUNT_WIDTH

export START_SCRIPT="start-sov.sh"
export STOP_SCRIPT="stop-sov.sh"
export RESET_SCRIPT="reset-sov.sh"
