# Gaia v17 Testnet Upgrades

* **Starting version:** Gaia `v16.0.0`
* **Upgrade version:** Gaia `v17.0.0-rc0`

> `Node upgrade duration` is the time it takes for a reference node to finish upgrading and start looking for peers after reaching the upgrade height.

> `Chain upgrade duration` is the time it takes for the chain to start producing blocks again after reaching the upgrade height.


## Release testnet (`theta-testnet-001`)

* **Upgrade height:** `21572600`
* **Upgrade time:** `2024-05-08T13:23:44Z`
* **Node upgrade duration:** 1m
* **Chain upgrade duration:** 9m
* [Proposal 249](https://explorer.polypore.xyz/theta-testnet-001/gov/249)

## Replicated Security testnet (`provider`)

* **Upgrade height:** `6183000`
* **Upgrade time:** `2024-05-08T14:11:13Z`
* **Node upgrade duration:** 1m
* **Chain upgrade duration:** 12m
* **Validators present:** 42/52
* [Proposal 122](https://explorer.polypore.xyz/provider/gov/122)

## Interchain Security Lightning Experiment (ISLE)

ISLE was a one-week incentivized testnet used to introduce validators to the features in Partial Set Security (also known as Interchain Security 2.0), the main feature of Gaia v17.

A total of five consumer chains were launched:
* Two Top N chains
* Three Opt-in chains

Validators were encouraged to opt in, opt out, and set commission rates on most of these consumer chains.

For more details, visit the [cosmos/testnets repo](https://github.com/cosmos/testnets/tree/master/isle).
