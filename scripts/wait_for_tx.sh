#!/bin/bash
# Poll for a tx to be included in a block instead of relying on a fixed sleep.
# Broadcasting in "sync" mode returns as soon as CheckTx passes, before the
# tx is actually committed, so a single fixed-window query after a static
# sleep is racy against normal block-time jitter. This retries instead, and
# logs the chain height on every miss so a stalled chain (height not moving)
# is distinguishable in the logs from a tx that's just slow to land/index.
#
# Usage: wait_for_tx.sh <txhash> <home> [max_attempts]
# Waits $COMMIT_TIMEOUT seconds between attempts (default max_attempts: 30,
# i.e. 60s at the default $COMMIT_TIMEOUT of 2s).
# On success, prints the tx result (--output json) to stdout and exits 0.
# On failure, exits 1 after max_attempts * $COMMIT_TIMEOUT seconds.

txhash=$1
home=$2
max_attempts=${3:-30}

if [ -z "$txhash" ] || [ -z "$home" ]
then
    echo "Usage: wait_for_tx.sh <txhash> <home> [max_attempts]" >&2
    exit 1
fi

last_height=""
stalled_attempts=0

for attempt in $(seq 1 $max_attempts)
do
    sleep $COMMIT_TIMEOUT
    tx_result=$($CHAIN_BINARY --output json q tx $txhash --home $home 2>/dev/null)
    if [ -n "$tx_result" ]
    then
        echo "$tx_result"
        exit 0
    fi

    height=$($CHAIN_BINARY status --home $home 2>/dev/null | jq -r '.sync_info.latest_block_height // .SyncInfo.latest_block_height // empty')
    if [ -n "$height" ] && [ "$height" = "$last_height" ]
    then
        stalled_attempts=$((stalled_attempts+1))
    else
        stalled_attempts=0
    fi
    last_height=$height

    echo "Tx $txhash not found yet (attempt $attempt/$max_attempts, height=${height:-unknown}), retrying..." >&2
    if [ "$stalled_attempts" -ge 5 ]
    then
        echo "WARNING: chain height has not advanced for $stalled_attempts consecutive checks — block production may have stalled." >&2
    fi
done

echo "ERROR: tx $txhash was not found after $(($COMMIT_TIMEOUT*$max_attempts))s (last known height: ${last_height:-unknown}). Aborting." >&2
exit 1
