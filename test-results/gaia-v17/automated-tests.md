# Gaia v17 Upgrade Test Results

* **Target version:** `v17.0.0`
* **Starting version:** `v16.0.0`

## Test Summary

Upgrade workflows use two starting points: fresh and stateful genesis.

* Fresh genesis: A genesis file is initialized with three validators and the chain starts at height 1.
  * [GitHub Actions workflow](https://github.com/hyphacoop/cosmos-release-testing/actions/runs/9172804242)
  * [Log archive](./v17-logs-fresh-state.zip)
* Stafeul genesis: A genesis file is periodically exported from the Interchain Security testnet to provide a single validator with a majority voting power so it can start producing blocks on its own.
  * [GitHub Actions workflow](https://github.com/hyphacoop/cosmos-release-testing/actions/runs/9067810923)
  * [Log archive](./logs-stateful.zip)

### Baseline

| Test                      | Fresh | Stateful |
| ------------------------- | ----- | -------- |
| Transactions              | PASS  | PASS     |
| API endpoints             | PASS  | PASS     |
| RPC endpoints             | PASS  | PASS     |
| Consumer chain launches   | PASS  | PASS     |
| packet-forward-middleware | PASS  | N/A      |
| Liquid Staking Module     | PASS  | N/A      |
| IBC fee middleware        | PASS  | N/A      |
| IBC ratelimit Module      | PASS  | N/A      |
| Provider epochs           | PASS  | PASS     |

### v17-specific

| Test                 | Fresh | Stateful |
| -------------------- | ----- | -------- |
| Partial Set Security | PASS  | PASS     |

## Baseline test details

* Transactions
   * tx bank send
   * tx staking delegate
   * tx distribution withdraw-all-rewards
   * tx staking unbond
 * API endpoints
 * RPC endpoints
* Consumer chain launches
   * Verify CCV channel is established
   * Test IBC transfers
   * Test soft opt-out
   * ICS versions:
     * v3.3.0
     * v4.0.0
   * Mainnet chain versions:
     * Neutron v3.0.2
     * Stride v22.0.0
* packet-forward-middleware
   * Test two-way IBC transfers:
     * A>B>C>D: **Test chain** -> pfm1 chain -> pfm2 chain -> pfm3 chain
     * D>C>B>A: pfm3 chain -> pfm2 chain -> pfm1 chain -> **test chain**
* Liquid Staking Module
   * Bond
   * Tokenize
   * Transfer ownership of liquid tokens
   * ICA delegation
   * Tokenize vested funds in vesting wallet

### v17-specific test details

1. Partial Set Security
  * Top N consumer chain launches
  * Opt-in consumer chain launches
  * Opt-in and opt-out operations
  * Downtime infractions
  * Consumer commission rate

## Relayer version

* Hermes v1.8.0

## Cosmovisor versions

Cosmovisor-based upgrades are tested with the auto-download feature both turned on and off.

* v1.5.0
* v1.4.0
* v1.3.0
