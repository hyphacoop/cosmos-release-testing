#!/bin/bash
# Assert that every module's params snapshot is unchanged across an upgrade.
#
# Usage: tests/test_params_unchanged.sh <before.json> <after.json>
#
# Both files are expected to be the output of scripts/query_module_params.sh:
# a single JSON object keyed by module name. Each module's value is diffed
# independently so a failure names exactly which module changed.

before=$1
after=$2

modules=(
    auth
    consensus
    distribution
    feemarket
    gov
    ibc-transfer
    ica-host
    ica-controller
    liquid
    mint
    ratelimit
    slashing
    staking
    tokenfactory
    wasm
)

error=0
for module in "${modules[@]}"; do
    before_json=$(jq -S --arg m "$module" '.[$m]' "$before")
    after_json=$(jq -S --arg m "$module" '.[$m]' "$after")

    if [ "$before_json" == "$after_json" ]; then
        echo "PASS: $module params unchanged"
    else
        echo "FAIL: $module params changed"
        echo "> Before:"
        echo "$before_json"
        echo "> After:"
        echo "$after_json"
        echo "> Diff:"
        diff <(echo "$before_json") <(echo "$after_json") || true
        error=1
    fi
done

if [ "$error" == "1" ]; then
    echo "FAILED: one or more module params changed across the upgrade."
    exit 1
else
    echo "PASSED: all module params unchanged across the upgrade."
fi
