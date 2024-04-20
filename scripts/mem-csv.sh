#!/bin/sh

# Usage ./mem-csv.sh process_name output_file.csv

while true
do
    pid=$(pidof $1)
    if [ ! -z "$pid" ] ; then
        ps -o rss= $(pidof $1) | \
        ps -o rss= $(pidof htop) | awk '{printf strftime("%s")",%.0f\n", $1 / 1024 * 1024 *1024}'
    else
        echo "$(date +"%s"),0"
    fi > $2
    sleep 1
done