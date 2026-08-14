#!/bin/bash
# Poll for a tx to be included in a block instead of relying on a fixed sleep.
# Broadcasting in "sync" mode returns as soon as CheckTx passes, before the
# tx is actually committed, so a single fixed-window query after a static
# sleep is racy against normal block-time jitter. This retries instead.
#
# Usage: wait_for_tx.sh <txhash> <home> [max_attempts]
# Waits $COMMIT_TIMEOUT seconds between attempts (default max_attempts: 10).
# On success, prints the tx result (--output json) to stdout and exits 0.
# On failure, exits 1 after max_attempts * $COMMIT_TIMEOUT seconds.

txhash=$1
home=$2
max_attempts=${3:-10}

if [ -z "$txhash" ] || [ -z "$home" ]
then
    echo "Usage: wait_for_tx.sh <txhash> <home> [max_attempts]" >&2
    exit 1
fi

for attempt in $(seq 1 $max_attempts)
do
    sleep $COMMIT_TIMEOUT
    tx_result=$($CHAIN_BINARY --output json q tx $txhash --home $home 2>/dev/null)
    if [ -n "$tx_result" ]
    then
        echo "$tx_result"
        exit 0
    fi
    echo "Tx $txhash not found yet (attempt $attempt/$max_attempts), retrying..." >&2
done

echo "ERROR: tx $txhash was not found after $(($COMMIT_TIMEOUT*$max_attempts))s. Aborting." >&2
exit 1
