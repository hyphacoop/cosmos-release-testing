#!/bin/bash
# Configure variables before running this file.
# source vars.sh

echo "> Creating arrays"

homes=()
for i in $(seq -w 001 $validator_count)
do
    home=$home_prefix$i
    homes+=($home)
    log=$log_prefix$i
    logs+=($log)
done

echo "> Enabling state sync"
toml set --toml-path ${homes[-1]}/config/app.toml state-sync.snapshot-interval $STATE_SYNC_INTERVAL


echo "> Restarting nodes."
./stop.sh
./start.sh
sleep 10
tail -n 100 ${logs-1}