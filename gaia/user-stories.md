# Gaia User Stories

The user stories in this document drive the validation tests that are run for each Gaia release. The user stories are split into several roles:
* Validator
* Delegator
* Interchain Security (ICS) - Consumer chain team
* ICS - Validator

## Validator

| As a validator, I want to:                    | so that:                                               |
| :-------------------------------------------- | :----------------------------------------------------- |
| **Setup**                                     |
| Join a network via snapshot                   | I can set up a node                                    |
| Check my node's sync status                   | I can verify my node is synced                         |
| Create an account                             | I can create a self-delegation account                 |
| Receive funds                                 |                                                        |
| Create a validator                            | I can operate a validator node                         |
| Query my validator status                     | I can verify my validator is signing blocks            |
| Unjail my validator                           | I can rejoin the active set                            |
| **Queries**                                   |
| Find out how much stake I have in delegations | I know how much delegators are staking in my validator |
| Find out my voting power                      | I know how much weight I have in consensus             |
| Check how many blocks I have missed           | I verify my node is participating in consensus         |
| **Governance**                                |
| Vote on proposals                             | I can participate in governance                        |
| Check my vote status                          | I can verify my vote was accepted                      |
| **Staking**                                   |
| Delegate stake                                | I can increase my self-delegation amount               |
| Undelegate stake                              | I can decrease my self-delegation amount               |
| Bond stake                                    | I can participate in liquid staking                    |
| Unbond stake                                  | I can stop participating in liquid staking             |

## Delegator

| As a validator, I want to:                            | so that:                                                  |
| :---------------------------------------------------- | :-------------------------------------------------------- |
| **bank**                                              |
| Receive funds                                         |
| Send funds                                            |
| **authz**                                             |
| Authorize grantee accounts                            | Somebody else can act on my behalf                        |
| Get grantee authorization                             | I can act on somebody else's behalf                       |
| **consensus**                                         |
| Update the consensus module params                    | Blocks no bigger than 50kb are allowed                    |
| **feegrant**                                          |
| Set up a grantee                                      | I can pay for somebody else's fees                        |
| Become a grantee                                      | Somebody can else can pay for my fees                     |
| **feemarket**                                         |
| Find out how much the gas price is                    | My transactions don't fail                                |
| Update the feemarket module params                    | The max block utilization is updated                      |
| **gov**                                               |
| Submit a proposal                                     | People can deposit                                        |
| Deposit on a proposal                                 | People can vote                                           |
| Vote on a proposal                                    | I can participate in governance                           |
| Submit a weighted vote                                | I can split my vote                                       |
| Check my vote status                                  | I can verify my vote was accepted                         |
| Check my proposal status                              | I know if my proposal will pass or not                    |
| Find out what the voting period is                    | I can prepare my proposal accordingly                     |
| Update gov module params                              | I can set the minimum deposit amount                      |
| Use the gov module account as an owner in a message   | I can make a proposal on behalf of the governance account |
| **ibc**                                               |
| Create client                                         | I can create a channel                                    |
| Create connection                                     | I can create a channel                                    |
| Create channel                                        | I can transfer funds via IBC                              |
| Send tokens via IBC                                   |                                                           |
| Receive tokens via IBC                                |                                                           |
| **interchain-accounts**                               |
| Register an interchain account in another chain       | I can submit transactions in another chain                |
| Register a gov interchain account in another chain    | I can submit gov proposals in another chain               |
| Generate ICA packet data                              | I can submit ICA transactions                             |
| Send an interchain account transaction                | I can interact with another chain                         |
| **sign**                                              |
| Generate an offline transaction                       | I can sign a transaction offline                          |
| Sign an offline transaction                           | I can submit a transaction                                |
| Submit a signed transaction                           |
| Create a multisig                                     | I can share custody of assets with other accounts         |
| Sign a multisig                                       | I can submit a transaction                                |
| Submit a signed multisig transaction                  |
| **staking**                                           |
| Stake                                                 | I can collect rewards                                     |
| Undelegate                                            | I can make my funds liquid                                |
| Redelegate                                            | I can switch validators                                   |
| Collect rewards                                       | I can make my funds liquid                                |
| Tokenize shares                                       | I can participate in liquid staking                       |
| Query the status of validators I have delegated to    | I know where my bonded funds are                          |
| Update the staking module params                      | I can set the max validators                              |
| **upgrade**                                           |
| Trigger a software upgrade via gov proposal           | The chain upgrades                                        |
| Trigger a software upgrade via expedited gov proposal | The chain upgrades in a shorter amount of time            |
| **vesting**                                           |
| Create a vesting account                              |
| Query vested amount                                   | Find out the amount of funds I have available             |
| Withdraw funds from a vesting account                 |
| Delegate with funds from a vesting account            |
| Tokenize delegations from a vesting account           | I can participate in liquid staking with vested funds     |
| **wasm**                                              |
| Store a new contract                                  | I can execute a contract                                  |
| Instantiate a new contract                            | I can execute a contract                                  |
| Execute a contract                                    |                                                           |

## ICS - Consumer Chain Team

| As a consumer chain team, I want to:                   | so that:                                                  |
| :----------------------------------------------------- | :-------------------------------------------------------- |
| Find out which consumer chains are online              | I know how many chains have successfully launched         |
| Launch an opt-in chain                                 | I can use the Hub security                                |
| Launch a top N chain                                   | I can use the Hub security                                |
| Transition my sovereign chain to a consumer one        | I can use the Hub security                                |
| Modify power shaping parameters                        | I can tune the chain launch adequately                    |
| Modify initialization parameters                       | I can tune the chain launch adequately                    |
| Modify consumer chain metadata                         | I can tune the chain launch adequately                    |
| Make sure the chain is interchain-secured after launch | I can sell the idea of joining the chain to other parties |
| Make sure rewards are being received in the provider   | Validators and delegators can collect rewards             |
| Remove a chain                                         | I can make a clean exit                                   |
| Find out how much the provider gas price is            | My transactions don't fail                                |

## ICS - Validator

| As a validator participating in ICS, I want to: | so that:                                                            |
| :---------------------------------------------- | :------------------------------------------------------------------ |
| Find out which consumer chains are online       | I can decide on which ones to join                                  |
| Assign keys to a consumer chain                 | I don't reuse my provider chain key                                 |
| Opt-in to a consumer chain                      | I can collect rewards for that chain                                |
| Query my validator status                       | I can verify my validator was set up properly and is signing blocks |
| Check how many blocks I have missed             | I verify my node is participating in consensus                      |
| Opt-out from a consumer chain                   | I don't have to run as much infra                                   |
| Set a consumer commission rate                  | I collect an adequate amount of tokens in a consumer chain          |
| Collect rewards from a consumer chain           | I can earn tokens from running additional infra                     |
| Submit double signing evidence                  | Misbehaving validators are tombstoned                               |
