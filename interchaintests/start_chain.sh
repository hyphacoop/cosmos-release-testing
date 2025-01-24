#!/usr/bin/env bash

# Clone interchaintest
if [[ ! -d interchaintest ]]; then
    git clone https://github.com/strangelove-ventures/interchaintest.git
fi
cd interchaintest/local-interchain
git fetch
pulled=0
if [[ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]]; then
    echo "Local interchain is out of date. Pulling latest changes..."
    git pull
    pulled=1
fi
if [[ $pulled -eq 1 ]] || [[ ! -f ../bin/local-ic ]]; then
    echo "Building local interchain..."
    make clean
    make build
fi
cd ..
LOCAL_IC=$(pwd)/bin/local-ic
cd ..
export ICTEST_HOME=$(pwd)

chain_config=$1
if [ -z "$chain_config" ]; then
    echo "Usage: $0 <chain_config>"
    echo "Check inside chains/ to see available chain configurations"
    exit 1
fi

sudo $LOCAL_IC start $chain_config &
sleep 30s
curl -s http://localhost:26657/status | jq '.'