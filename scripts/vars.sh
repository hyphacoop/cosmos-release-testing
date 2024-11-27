export validator_count=5

# Upgrade configuration
export UPGRADE_VERSION=v21.0.1
export UPGRADE_BINARY_SOURCE=DOWNLOAD
export UPGRADE_BINARY_URL=https://github.com/cosmos/gaia/releases/download/$UPGRADE_VERSION/gaiad-$UPGRADE_VERSION-linux-amd64

# Provider configuration
export CHAIN_VERSION=v20.0.0
export CHAIN_BINARY_URL=https://github.com/cosmos/gaia/releases/download/$CHAIN_VERSION/gaiad-$CHAIN_VERSION-linux-amd64
export CHAIN_BINARY="./gaiad"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl
export VALOPER_1=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv
export CHAIN_ID=testnet
export DENOM=uatom
export VAL_FUNDS="10000000000"
export VAL_WHALE="100000000"
export VAL_STAKE="1000000"
export DOWNTIME_WINDOW="10"
export EXPEDITED_VOTING_PERIOD="10"
export VOTING_PERIOD="30"
export VOTING_PERIODS="30s"
export DEPOSIT_PERIOD="60"
export DEPOSIT_PERIODS="60s"
export TIMEOUT_COMMIT="5"
export TIMEOUT_COMMITS="${TIMEOUT_COMMIT}s"
export GAS_PRICE=0.005$DENOM
export GAS=auto
export GAS_ADJUSTMENT=3

export moniker_prefix='val_'
export home_prefix='temp/.val_'
export whale_home=${home_prefix}001
export api_prefix="25"
export p2p_prefix="26"
export rpc_prefix="27"
export grpc_prefix="28"
export pprof_prefix="29"
export log_prefix="log_"

# Consumer configuration
export SPAWN_TIME_WAIT="15"
export SPAWN_TIME_OFFSET="${SPAWN_TIME_WAIT} secs"
export CONSUMER_CHAIN_ID=consumer
export CONSUMER_CHAIN_BINARY="./ics"
export CONSUMER_DENOM="ucon"
export CONSUMER_GAS_PRICE=0.005$CONSUMER_DENOM
export CONSUMER_WALLET_1="consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc"
export consumer_moniker_prefix='con_'
export consumer_home_prefix="contemp/.$consumer_moniker_prefix"
export consumer_whale_home=${consumer_home_prefix}001
export consumer_api_prefix="35"
export consumer_p2p_prefix="36"
export consumer_rpc_prefix="37"
export consumer_grpc_prefix="38"
export consumer_pprof_prefix="39"

# Relayer configuration
export HERMES_VERSION="v1.10.3"
export HERMES_BINARY="./hermes"