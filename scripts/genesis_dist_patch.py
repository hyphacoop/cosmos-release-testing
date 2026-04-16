#!/usr/bin/env python3
"""
Reconcile distribution module DecCoins accounting in an exported Cosmos SDK genesis file.

Fixes the "distribution module balance does not match the module holdings" panic
that can occur on genesis import when the distribution module's DecCoins sum
(community pool + outstanding validator rewards) exceeds the module's actual
bank balance due to accumulated truncation dust.

Usage:
    python3 reconcile_distribution.py genesis.json
    python3 reconcile_distribution.py genesis.json -o reconciled_genesis.json
    python3 reconcile_distribution.py genesis.json --dry-run
"""

import argparse
import json
import sys
from decimal import Decimal, getcontext

# Match the 18-decimal precision used by sdk.Dec / DecCoins.
getcontext().prec = 36


def find_distribution_address(auth_accounts):
    """Find the distribution module account address from the auth module state."""
    for acct in auth_accounts:
        if acct.get("name") == "distribution":
            base = acct.get("base_account")
            if base:
                return base.get("address")
            return acct.get("address")

        # Handle nested module account structure (varies by SDK version).
        if acct.get("@type", "").endswith("ModuleAccount"):
            if acct.get("name") == "distribution":
                base = acct.get("base_account")
                if base:
                    return base.get("address")
    return None


def get_bank_balance(bank_balances, address):
    """Return a {denom: int_amount} dict for the given address."""
    for entry in bank_balances:
        if entry["address"] == address:
            return {
                coin["denom"]: int(coin["amount"])
                for coin in entry.get("coins", [])
            }
    return {}


def sum_dec_coins(coin_list, totals):
    """Add a list of DecCoin entries ({denom, amount}) into the totals dict."""
    for coin in coin_list:
        denom = coin["denom"]
        amount = Decimal(coin["amount"])
        totals[denom] = totals.get(denom, Decimal(0)) + amount


def compute_holdings(distr_state):
    """Sum all DecCoins the distribution module tracks: community pool + outstanding rewards."""
    totals = {}

    community_pool = distr_state.get("fee_pool", {}).get("community_pool", [])
    sum_dec_coins(community_pool, totals)

    for entry in distr_state.get("outstanding_rewards", []):
        rewards = entry.get("outstanding_rewards", [])
        sum_dec_coins(rewards, totals)

    return totals


def compute_adjustments(dec_totals, bank_bal):
    """Find denoms where truncated DecCoins exceed the bank balance."""
    adjustments = {}
    for denom, dec_total in dec_totals.items():
        truncated = int(dec_total)
        bank_amount = bank_bal.get(denom, 0)
        if truncated > bank_amount:
            adjustments[denom] = truncated - bank_amount
    return adjustments


def apply_adjustments(community_pool, adjustments):
    """Subtract adjustment amounts from community pool DecCoins entries."""
    for coin in community_pool:
        denom = coin["denom"]
        if denom in adjustments:
            old_val = Decimal(coin["amount"])
            new_val = old_val - Decimal(adjustments[denom])
            coin["amount"] = f"{new_val:.18f}"
            yield denom, old_val, new_val


def main():
    parser = argparse.ArgumentParser(
        description="Reconcile distribution module accounting in an exported genesis file."
    )
    parser.add_argument(
        "genesis",
        help="Path to the exported genesis JSON file.",
    )
    parser.add_argument(
        "-o", "--output",
        help="Output path for the reconciled genesis. Defaults to overwriting the input file.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print adjustments without modifying the file.",
    )
    args = parser.parse_args()

    with open(args.genesis) as f:
        genesis = json.load(f)

    app_state = genesis.get("app_state", {})
    distr_state = app_state.get("distribution", {})
    bank_state = app_state.get("bank", {})
    auth_state = app_state.get("auth", {})

    # Find the distribution module address.
    distr_addr = find_distribution_address(auth_state.get("accounts", []))
    if not distr_addr:
        print("ERROR: could not find distribution module account in auth state.", file=sys.stderr)
        sys.exit(1)
    print(f"Distribution module address: {distr_addr}")

    # Get the bank balance.
    bank_bal = get_bank_balance(bank_state.get("balances", []), distr_addr)
    print(f"Distribution bank balance: {len(bank_bal)} denoms")

    # Sum DecCoins holdings.
    dec_totals = compute_holdings(distr_state)
    print(f"Distribution DecCoins holdings: {len(dec_totals)} denoms")

    # Find adjustments.
    adjustments = compute_adjustments(dec_totals, bank_bal)
    if not adjustments:
        print("No adjustments needed — accounting is consistent.")
        sys.exit(0)

    print(f"\nAdjustments required for {len(adjustments)} denom(s):")
    for denom, amount in sorted(adjustments.items()):
        truncated = int(dec_totals[denom])
        bank_amount = bank_bal.get(denom, 0)
        print(f"  {denom}: holdings={truncated} bank={bank_amount} overshoot={amount}")

    if args.dry_run:
        print("\nDry run — no changes written.")
        sys.exit(0)

    # Apply adjustments to community pool.
    community_pool = distr_state.get("fee_pool", {}).get("community_pool", [])
    changes = list(apply_adjustments(community_pool, adjustments))

    print(f"\nApplied {len(changes)} community pool adjustment(s):")
    for denom, old_val, new_val in changes:
        print(f"  {denom}: {old_val} -> {new_val}")

    # Verify all adjustments were applied (every adjusted denom must exist in the community pool).
    applied_denoms = {denom for denom, _, _ in changes}
    missed = set(adjustments.keys()) - applied_denoms
    if missed:
        print(f"\nWARNING: {len(missed)} denom(s) not found in community pool: {missed}", file=sys.stderr)
        print("These denoms may be entirely in outstanding rewards with no community pool entry.", file=sys.stderr)
        print("Manual inspection required.", file=sys.stderr)

    # Write output.
    output_path = args.output or args.genesis
    with open(output_path, "w") as f:
        json.dump(genesis, f, indent=2)
        f.write("\n")

    print(f"\nReconciled genesis written to: {output_path}")


if __name__ == "__main__":
    main()