
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v7.0.1/interchain-security-cd-linux
export CONSUMER_CHAIN_BINARY_NAME="consumerd-v701-two"
export CONSUMER_CHAIN_BINARY="$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=v701-two
export CONSUMER_DENOM=ucon

export CONSUMER_DOWNTIME_WINDOW=100000
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_DENOM=ucon
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=cd-transform
export CONSUMER_ICS="v6.4.0"

export consumer_moniker_prefix='con702_'
export consumer_home_prefix='/home/runner/.con702_'
export consumer_api_prefix="271"
export consumer_p2p_prefix="272"
export consumer_rpc_prefix="273"
export consumer_grpc_prefix="274"
export consumer_pprof_prefix="275"
export consumer_log_prefix="con702log_"

export consumer_whale_home=${consumer_home_prefix}01
export consumer_whale_rpc=${consumer_rpc_prefix}01