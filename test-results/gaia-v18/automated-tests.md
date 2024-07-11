# Gaia v17 Upgrade Test Results

* **Target version:** `v18.1.0`
* **Starting version:** `v17.2.0`

## Test Summary

Upgrade workflows use two starting points: fresh and stateful genesis.

* Fresh genesis: A genesis file is initialized with six validators and the chain starts at height 1.
  * [GitHub Actions workflow]()
  * [Log archive]()
* Stafeul genesis: A genesis file is periodically exported from the Interchain Security testnet to provide a single validator with a majority voting power so it can start producing blocks on its own.
  * [GitHub Actions workflow]()
  * [Log archive]()

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
| ICA Controller Module     | PASS  | N/A      |
| Provider epochs           | PASS  | PASS     |
| Partial Set Security      | PASS  | PASS     |

### v18-specific

| Test                 | Fresh | Stateful |
| -------------------- | ----- | -------- |
| Cosmwasm             | PASS  | N/A      |
| Feemarket            | PASS  | PASS     |

## Baseline test details

* Transactions
   * tx bank send
   * tx staking delegate
   * tx distribution withdraw-all-rewards
   * tx staking unbond
   * tx authz grants with:
      * send
      * delegate
      * unbond
      * redelegate
      * generic with MsgVote
    * Feegrants
      * Fee is paid from granting account
      * Fee isn't paid from granting account once grant expires/is revoked
    * Multisig transactions
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
* IBC fee middleware
  * A relayer channel is created with the ibc fee middleware enabled
  * It must be possible to use `ibc-fee pay-packet-fee` to incentivize transaction
  * Fee funds in sender address must be escrowed
  * Fee must be added to the relayer account's balance
  * Relayer channels without the middleware enabled must work as they did before
* IBC rate limiting
  * The rate limit `max_percent_send` is set to `2%` via gov proposal
  * It must not be possible to send `2%` of the supply to another chain
  * It must be possible to send `1%` of the supply once
  * The second time `1%` is sent, it must fail
* ICA controller module
  * An ICA account is set-up with a v16 controller chain
  * It must be possible to fund the account via IBC transfer from the controller
  * The controller must be able to use `interchain-accounts controller send-tx` to send to an address on the host
* Provider epochs
  * `BlocksPerEpoch` gov parameter is set to `20`
  * Delegations in provider chain must take 20 blocks to be reflected in consumer chains
  * It must not be possible to set `BlocksPerEpoch < 1`
* Partial Set Security
  * Top N consumer chain launches
  * Opt-in consumer chain launches
  * Opt-in and opt-out operations
  * Power cap
  * Validator set cap
  * Downtime infractions
  * Consumer commission rate

### v18-specific test details

* Cosmwasm
  * Instantiate a contract via proposal
  * It mustn't be possible to store or instantiate a contract with no proposal
  * Execute contract both via `wasm execute` and via proposal
* Feemarket
  * Set MaxBlockUtilization to 1000000
  * Execute 600 transactions per block
  * Ensure that gas price increases monotonically

## Relayer version

* Hermes v1.8.0

## Cosmovisor versions

Cosmovisor-based upgrades are tested with the auto-download feature both turned on and off.

* v1.5.0
* v1.4.0
* v1.3.0
