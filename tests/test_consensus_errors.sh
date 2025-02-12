#!/bin/bash 
# Check the logs are clear of wrong apphash errors.
APPHASH_ERROR='consensus deems this block invalid'
LOOKBACK=50
apphash=$(journalctl -u $PROVIDER_SERVICE_1 | grep -c "$APPHASH_ERROR" || true)
if [ $apphash != "0" ]; then
  echo "AppHash error found!"
  journalctl -u $PROVIDER_SERVICE_1 | tail -n $LOOKBACK
  exit 1
fi
apphash=$(journalctl -u $PROVIDER_SERVICE_2 | grep -c "$APPHASH_ERROR" || true)
if [ $apphash != "0" ]; then
  echo "AppHash error found!"
  journalctl -u $PROVIDER_SERVICE_2 | tail -n $LOOKBACK
  exit 1
fi
apphash=$(journalctl -u $PROVIDER_SERVICE_3 | grep -c "$APPHASH_ERROR" || true)
if [ $apphash != "0" ]; then
  echo "AppHash error found!"
  journalctl -u $PROVIDER_SERVICE_3 | tail -n $LOOKBACK
  exit 1
fi
