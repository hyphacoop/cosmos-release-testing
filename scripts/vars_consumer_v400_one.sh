
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v4.0.0/interchain-security-cd-linux
export CONSUMER_CHAIN_BINARY_NAME="consumerd-v400-one"
export CONSUMER_CHAIN_BINARY="$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=v400-one
export CONSUMER_DENOM=ucon

export CONSUMER_DOWNTIME_WINDOW=20
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_DENOM=ucon
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=$CONSUMER_CHAIN_BINARY
export CONSUMER_ICS="v4.0.0"

export consumer_moniker_prefix='con400_'
export consumer_home_prefix='/home/runner/.con400_'
export consumer_api_prefix="401"
export consumer_p2p_prefix="402"
export consumer_rpc_prefix="403"
export consumer_grpc_prefix="404"
export consumer_pprof_prefix="405"
export consumer_log_prefix="con40log_"

export consumer_whale_home=${consumer_home_prefix}01
export consumer_whale_rpc=${consumer_rpc_prefix}01
