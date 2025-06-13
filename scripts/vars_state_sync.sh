# Chain configuration
export CHAIN_BINARY_NAME="gaiad"
export CHAIN_BINARY="./$CHAIN_BINARY_NAME"

# Provider configuration
export CHAIN_ID=testnet
export DENOM=uatom
export GAS_PRICE=0.005$DENOM

export node_home='/home/runner/.statesync'
export home_prefix='/home/runner/.val_'
export whale_home=${home_prefix}001
export api_prefix="25"
export p2p_prefix="26"
export rpc_prefix="27"
export grpc_prefix="28"
export pprof_prefix="29"

export START_SCRIPT="start-statesync.sh"
export STOP_SCRIPT="stop-statesync.sh"
export RESET_SCRIPT="reset-statesync.sh"
