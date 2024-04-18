# Gaia v16 Upgrade Test Results

* **Target version:** `v16.0.0`
* **Starting version:** `v15.2.0`
* **Minimum hardware requirements for stateful upgrade**
  * 8 cores
  * 64GB memory + 32GB swap
* **Recommended hardware requirements for stateful upgrade**
  * 8 cores
  * 128GB memory
  * NVME storage

## Test Summary

Upgrade workflows use two starting points: fresh and stateful genesis.

* Fresh genesis: A genesis file is initialized with three validators and the chain starts at height 1.
  * [GitHub Actions workflow](https://github.com/hyphacoop/cosmos-release-testing/actions/runs/8740189079/job/23983327051)
  * [Log archive]()
* Stafeul genesis: A genesis file is periodically exported from a Cosmos Hub node and modified to provide a single validator with a majority voting power so it can start producing blocks on its own.
  * [GitHub Actions workflow]()
  * [Log archive]()

### Baseline

| Test                      | Fresh | Stateful |
| ------------------------- | ----- | -------- |
| Transactions              | PASS  | ?        |
| API endpoints             | PASS  | ?        |
| RPC endpoints             | PASS  | ?        |
| Consumer chain launches   | PASS  | N/A      |
| packet-forward-middleware | PASS  | N/A      |
| Liquid Staking Module     | PASS  | N/A      |
| Mainnet consumer chains   | PASS  | N/A      |

### v16-specific

| Test                    | Fresh | Stateful |
| ----------------------- | ----- | -------- |
| Tokenize vested amount  | PASS  | N/A      |
| Blocks Per Epoch        | PASS  | N/A      |
| IBC fee middleware      | PASS  | N/A      |
| IBC rate limiting       | PASS  | ?        |
| ICA controller module   | PASS  | N/A      |

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
* packet-forward-middleware
   * Test two-way IBC transfers:
     * A>B>C>D: **Test chain** -> pfm1 chain -> pfm2 chain -> pfm3 chain
     * D>C>B>A: pfm3 chain -> pfm2 chain -> pfm1 chain -> **test chain**
* Liquid Staking Module
   * Bond
   * Tokenize
   * Transfer ownership of liquid tokens
   * ICA delegation

### v16-specific test details

1. Tokenize vested amount
    * A vesting account is created, the total amount is delegated, half the amount vests
    * It must be possible to tokenize half the total amount (the vested amount)
    * It must not be possible to tokenize the full amount
2. Blocks Per Epoch
    * `BlocksPerEpoch` gov parameter is set to `20`
    * Delegations in provider chain must take 20 blocks to be reflected in consumer chains
    * It must not be possible to set `BlocksPerEpoch < 1`
3. IBC fee middleware
    * A relayer channel is created with the ibc fee middleware enabled
    * It must be possible to use `ibc-fee pay-packet-fee` to incentivize transaction
    * Fee funds in sender address must be escrowed
    * Fee must be added to the relayer account's balance
    * Relayer channels without the middleware enabled must work as they did before
4. IBC rate limiting
    * The rate limit `max_percent_send` is set to `2%` via gov proposal
    * It must not be possible to send `2%` of the supply to another chain
    * It must be possible to send `1%` of the supply once
    * The second time `1%` is sent, it must fail
5. ICA controller module
    * An ICA account is set-up with a v16 controller chain
    * It must be possible to fund the account via IBC transfer from the controller
    * The controller must be able to use `interchain-accounts controller send-tx` to send to an address on the host

## Relayer version

* Hermes v1.8.0

<!--
interchaintest doesn't currently use Cosmovisor.

## Cosmovisor versions

Cosmovisor-based upgrades are tested with the auto-download feature both turned on and off.

* v1.5.0
* v1.4.0
* v1.3.0
-->
