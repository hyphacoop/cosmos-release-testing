
export CONSUMER_CHAIN_BINARY_NAME="consumerd"
export CONSUMER_CHAIN_BINARY="$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=v400-one
export CONSUMER_DENOM=ucon

export CONSUMER_DOWNTIME_WINDOW=100000
export RECIPIENT=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
export CONSUMER_DENOM=ucon
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=cd-transform

export consumer_moniker_prefix='con_'
export consumer_home_prefix='/home/runner/.con_'
export whale_home_consumer=${consumer_home_prefix}001
export consumer_api_prefix="35"
export consumer_p2p_prefix="36"
export consumer_rpc_prefix="37"
export consumer_grpc_prefix="38"
export consumer_pprof_prefix="39"
export consumer_log_prefix="conlog_"