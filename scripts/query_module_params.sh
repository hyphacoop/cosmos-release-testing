#!/bin/bash
# Query every module's on-chain params and assemble them into a single JSON
# object, keyed by module name. Intended to be called once before an upgrade
# and once after, then diffed with tests/test_params_unchanged.sh.
#
# Notes:
# - authz and feegrant are intentionally excluded: neither module exposes a
#   Params query (no Params message exists for them).
# - ratelimit has no Params query either; list-rate-limits is used as a proxy
#   for its "params" since it holds the module's configured rate limits.
#
# Expects scripts/vars.sh to already be sourced ($CHAIN_BINARY, $whale_home).

set -euo pipefail

q() {
    # $1: module + subcommand args (e.g. "auth params")
    $CHAIN_BINARY q $1 --home "$whale_home" -o json
}

jq -n \
    --argjson auth "$(q 'auth params')" \
    --argjson consensus "$(q 'consensus params')" \
    --argjson distribution "$(q 'distribution params')" \
    --argjson feemarket "$(q 'feemarket params')" \
    --argjson gov "$(q 'gov params')" \
    --argjson ibc_transfer "$(q 'ibc-transfer params')" \
    --argjson ica_host "$(q 'interchain-accounts host params')" \
    --argjson ica_controller "$(q 'interchain-accounts controller params')" \
    --argjson liquid "$(q 'liquid params')" \
    --argjson mint "$(q 'mint params')" \
    --argjson ratelimit "$(q 'ratelimit list-rate-limits')" \
    --argjson slashing "$(q 'slashing params')" \
    --argjson staking "$(q 'staking params')" \
    --argjson tokenfactory "$(q 'tokenfactory params')" \
    --argjson wasm "$(q 'wasm params')" \
    '{
        "auth": $auth,
        "consensus": $consensus,
        "distribution": $distribution,
        "feemarket": $feemarket,
        "gov": $gov,
        "ibc-transfer": $ibc_transfer,
        "ica-host": $ica_host,
        "ica-controller": $ica_controller,
        "liquid": $liquid,
        "mint": $mint,
        "ratelimit": $ratelimit,
        "slashing": $slashing,
        "staking": $staking,
        "tokenfactory": $tokenfactory,
        "wasm": $wasm
    }' | jq -S '.'
