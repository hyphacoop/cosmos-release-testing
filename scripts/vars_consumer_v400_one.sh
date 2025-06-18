
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v4.0.0/interchain-security-cd-linux
export CONSUMER_CHAIN_BINARY_NAME="consumerd-v400-one"
export CONSUMER_CHAIN_BINARY="$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=v400-one
export CONSUMER_DENOM=ucon

export CONSUMER_DOWNTIME_WINDOW=100000
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_DENOM=ucon
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=$CONSUMER_CHAIN_BINARY

export consumer_moniker_prefix='con_'
export consumer_home_prefix='/home/runner/.con_'
export whale_home_consumer=${consumer_home_prefix}001
export consumer_api_prefix="40"
export consumer_p2p_prefix="40"
export consumer_rpc_prefix="40"
export consumer_grpc_prefix="40"
export consumer_pprof_prefix="40"
export consumer_log_prefix="con40log_"