
export CONSUMER_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export CONSUMER_CHAIN_BINARY_NAME="strided"
export CONSUMER_CHAIN_BINARY="$CONSUMER_CHAIN_BINARY_NAME"
export CONSUMER_CHAIN_ID=stride-test
export CONSUMER_DENOM=ustrd

export CONSUMER_DOWNTIME_WINDOW=100000
export RECIPIENT=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM

export ICS_TRANSFORM_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v3.3.0-transform/interchain-security-cd
export ICS_TRANSFORM_BINARY=cd-transform
export CONSUMER_ICS="v4.0.0"

export consumer_moniker_prefix='stride_'
export consumer_home_prefix='/home/runner/.stride_'
export consumer_api_prefix="311"
export consumer_p2p_prefix="312"
export consumer_rpc_prefix="313"
export consumer_grpc_prefix="314"
export consumer_pprof_prefix="315"
export consumer_log_prefix="stridelog_"

export consumer_whale_home=${consumer_home_prefix}01
export consumer_whale_rpc=${consumer_rpc_prefix}01