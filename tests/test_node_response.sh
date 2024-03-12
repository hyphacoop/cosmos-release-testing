#!/bin/bash 
# Test if node is online.

gaia_host=$1
gaia_port=$2
max_attempts=${3:-20}
# Waiting until node responds
attempt_counter=0
# max_attempts=8000
echo "Waiting for node to come back online..."
until $(curl --output /dev/null --silent --head --fail http://$gaia_host:$gaia_port)
do
    if [ ${attempt_counter} -gt ${max_attempts} ]
    then
        echo ""
        journalctl -u $PROVIDER_SERVICE_1 | tail -n 20
        echo "Tried connecting to node for $attempt_counter times. Exiting."
        exit 3
    fi
    printf '.'
    attempt_counter=$(($attempt_counter+1))
    sleep 1
done
