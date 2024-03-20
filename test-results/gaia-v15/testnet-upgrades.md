# Gaia v15 Testnet Upgrades

* **Starting version:** Gaia `v14.1.0`
* **Upgrade version:** Gaia `v15.0.0-rc0`

> `Node upgrade duration` is the time it takes for a reference node to finish upgrading and start looking for peers after reaching the upgrade height.

> `Chain upgrade duration` is the time it takes for the chain to start producing blocks again after reaching the upgrade height.


## Release testnet (`theta-testnet-001`)

* **Upgrade height:** `20269900`
* **Upgrade time:** `2024-02-13T15:09:28Z`
* **Node upgrade duration:** 13m
* **Chain upgrade duration:** 55m
* [Proposal 216](https://explorer.polypore.xyz/theta-testnet-001/gov/216)

Additional coordinated upgrades were used to upgrade the network to newer release candidates:

* `v15.0.0-rc1`
  * **Upgrade height**: `20378500`
* `v15.0.0-rc3`
  * **Upgrade height**: `20519000`

## Replicated Security testnet (`provider`)

* **Upgrade height:** `5208900`
* **Upgrade time:** `2024-02-14T15:02:26Z`
* **Node upgrade duration:** 10m
* **Chain upgrade duration:** 41m
* **Validators present:** 41/59
* [Proposal 107](https://explorer.polypore.xyz/provider/gov/107)

Additional coordinated upgrades were used to upgrade the network to newer release candidates:

* `v15.0.0-rc1`
  * **Upgrade height**: `20378500`
* `v15.0.0-rc3`
  * **Upgrade height**: `20519000`

## Mini Testnet (`local-testnet`)

### Upgrade version: `v15.1.0-rc1`

The Cosmos Hub (`cosmoshub-4`) network was upgraded from `v14.1.0` to `v14.2.0` after the testnets upgraded from `v14.1.0` to `v15.0.0`.  
A short-lived stateful testnet was created with five validators to verify the `v14.2.0` -> `v15.1.0` upgrade path.  
This testnet was started using a modified Cosmos Hub genesis export at height `19610394`.

* **Upgrade height:** `19611800`
* **Upgrade time:** `2024-03-18T18:15:02Z`
* **Node upgrade duration:** 40-90m
* **Chain upgrade duration:** 90m
* **Validators present:** 5
