# cosmos-release-testing

Automated testing for Cosmos builds

## Test Workflows

### Gaia Upgrade - Fresh State

To trigger an upgrade test starting from genesis, go to the [Actions page](https://github.com/hyphacoop/cosmos-release-testing/actions/workflows/upgrade-gaia-fresh-state.yml) and click `Run workflow`.
* Enter the versions to upgrade from and to, as well as the upgrade name.
  * If the upgrade version starts with a `v`, the worfklow will attempt to use a binary downloaded from the Gaia releases page.
  * If the upgrade version starts with any other character, the workflow will attempt to check out that version from the Gaia repo and build the binary to test with.
* Run the workflow.


### Mainnet Upgrade State Export

To generate a mainnet state export, trigger the workflow in [the Actions](https://github.com/hyphacoop/cosmos-release-testing/actions/workflows/export-mainnet-upgrade-states.yml) page after setting the following variables in the `export-cosmoshub-mainnet` environment:
* `FORK_TOOL_TAG`
* `UPGRADE_NAME`


### Gaia Upgrade - Stateful

An appropriate snapshot must be available for this workflow to run correctly see the previous section to generate one. To trigger an upgrade test using a Cosmos Hub fork, go to the [Actions page](https://github.com/hyphacoop/cosmos-release-testing/actions/workflows/upgrade-gaia-stateful.yml) and click `Run workflow`.
* Enter the versions to upgrade from and to, as well as a location for the fork snapshot. 
  * If the upgrade version is `main`, the workflow will attempt to check out that version from the Gaia repo and build the binary to test with.
  * If the upgrade version is not `main`, the worfklow will attempt to use a binary downloaded from the Gaia releases page.
* Run the workflow.


