
echo "validator_count=5" >> $GITHUB_ENV

# Upgrade configuration
echo "UPGRADE_VERSION=v21.0.0" >> $GITHUB_ENV
echo "UPGRADE_COMMIT=main" >> $GITHUB_ENV
echo "UPGRADE_BINARY_SOURCE=DOWNLOAD" >> $GITHUB_ENV
echo "UPGRADE_BINARY_URL=https://github.com/cosmos/gaia/releases/download/$UPGRADE_VERSION/gaiad-$UPGRADE_VERSION-linux-amd64" >> $GITHUB_ENV

# Test chain configuration
echo "CHAIN_VERSION=v20.0.0" >> $GITHUB_ENV
echo "CHAIN_BINARY_URL=https://github.com/cosmos/gaia/releases/download/$CHAIN_VERSION/gaiad-$CHAIN_VERSION-linux-amd64" >> $GITHUB_ENV
echo "CHAIN_BINARY=./gaiad" >> $GITHUB_ENV
echo "MNEMONIC_1=abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art" >> $GITHUB_ENV
echo "WALLET_1=cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl" >> $GITHUB_ENV
echo "VALOPER_1=cosmosvaloper1r5v5srda7xfth3hn2s26txvrcrntldju7lnwmv" >> $GITHUB_ENV
echo "CHAIN_ID=testnet" >> $GITHUB_ENV
echo "DENOM=uatom" >> $GITHUB_ENV
echo "VAL_FUNDS=10000000000" >> $GITHUB_ENV
echo "VAL_WHALE=100000000" >> $GITHUB_ENV
echo "VAL_STAKE=10000000" >> $GITHUB_ENV
echo "DOWNTIME_WINDOW=10" >> $GITHUB_ENV
echo "EXPEDITED_VOTING_PERIOD=10" >> $GITHUB_ENV
echo "VOTING_PERIOD=30" >> $GITHUB_ENV
echo "DEPOSIT_PERIOD=60" >> $GITHUB_ENV
echo "TIMEOUT_COMMIT=5" >> $GITHUB_ENV
echo "GAS_PRICE=0.005$DENOM" >> $GITHUB_ENV
echo "GAS=auto" >> $GITHUB_ENV
echo "GAS_ADJUSTMENT=3" >> $GITHUB_ENV

echo "moniker_prefix=val_" >> $GITHUB_ENV
echo "home_prefix=temp/.val_" >> $GITHUB_ENV
echo "whale_home=${home_prefix}001" >> $GITHUB_ENV
echo "api_prefix=25" >> $GITHUB_ENV
echo "p2p_prefix=26" >> $GITHUB_ENV
echo "rpc_prefix=27" >> $GITHUB_ENV
echo "grpc_prefix=28" >> $GITHUB_ENV
echo "pprof_prefix=29" >> $GITHUB_ENV
echo "log_prefix=log_" >> $GITHUB_ENV