
export validator_count=5
export CHANGEOVER_UPGRADE_NAME="sovereign-changeover"
export SOVEREIGN_CHAIN_BINARY_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v6.4.0/interchain-security-sd-linux
export CHAIN_BINARY_URL=$SOVEREIGN_CHAIN_BINARY_URL
export DOWNLOAD_URL=https://github.com/hyphacoop/cosmos-builds/releases/download/ics-v6.4.0/interchain-security-cd-linux
# Chain configuration
export CHAIN_BINARY_NAME="sovd"
export CHAIN_BINARY="./$CHAIN_BINARY_NAME"
export MNEMONIC_1="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
export WALLET_1=consumer1r5v5srda7xfth3hn2s26txvrcrntldju7725yc

export MNEMONIC_RELAYER="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon trouble"
export WALLET_RELAYER=consumer1jf7j9nvjmnflal5ehaj25p7nsk2t3lkd57l33x

export CHAIN_ID=v640-one
export DENOM=ucon
export VAL_FUNDS="10000000000"
export VAL_WHALE="100000000"
export VAL_STAKE="10000000"
export DOWNTIME_WINDOW="10"
export DOWNTIME_JAIL_DURATION="30s"
export EXPEDITED_VOTING_PERIOD="10"
export VOTING_PERIOD="30"
export DEPOSIT_PERIOD="60"
# export COMMIT_TIMEOUT="5"
export GAS_PRICE=0.005$DENOM
export GAS=auto
export GAS_ADJUSTMENT=3
export STATE_SYNC_SNAPSHOT_INTERVAL=0
export STATE_SYNC_SNAPSHOT_KEEP_RECENT=5

export COUNT_WIDTH="01"
export moniker_prefix='sov_'
export home_prefix='/home/runner/.sov_'
export api_prefix="641"
export p2p_prefix="642"
export rpc_prefix="643"
export grpc_prefix="644"
export pprof_prefix="645"
export log_prefix="sov_"

export whale_home=${home_prefix}$COUNT_WIDTH
export whale_api=${api_prefix}$COUNT_WIDTH
export whale_rpc=${rpc_prefix}$COUNT_WIDTH
export whale_log=${log_prefix}$COUNT_WIDTH

export START_SCRIPT="start-sov.sh"
export STOP_SCRIPT="stop-sov.sh"
export RESET_SCRIPT="reset-sov.sh"

export CONSUMER_CHAIN_BINARY_NAME="changeoverd"
export CONSUMER_CHAIN_BINARY="./$CONSUMER_CHAIN_BINARY_NAME"
