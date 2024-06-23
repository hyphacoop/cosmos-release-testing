#!/bin/bash

toml set --toml-path $HOME_1/config/config.toml consensus.timeout_commit "60s"
sudo systemctl restart $PROVIDER_SERVICE_1 --now
echo "Restarting node after setting timeout_commit to 1m..."
sleep 70s
echo "Loading mempool with large gas txs..."
scripts/gaia-v18/load_blocks.sh 50000000 30 0.005
echo "Loading mempool with txs..."
scripts/gaia-v18/load_blocks.sh 100000 5000 0.01
echo "Waiting for blocks to get loaded..."
num_unconfirmed_txs=$(curl -s http://localhost:$VAL1_RPC_PORT/num_unconfirmed_txs | jq -r '.result.n_txs')
echo "Unconfirmed txs: $num_unconfirmed_txs"
while [ $num_unconfirmed_txs -gt "1000" ] ; do
    echo "Sleeping for a minute..."
    sleep 1m
    num_unconfirmed_txs=$(curl -s http://localhost:$VAL1_RPC_PORT/num_unconfirmed_txs | jq -r '.result.n_txs')
    echo "Unconfirmed txs: $num_unconfirmed_txs"
done
echo "Less than 1000 txs remain in the mempool"