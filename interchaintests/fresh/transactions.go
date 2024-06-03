package fresh

import (
	"context"
	"encoding/json"
	"fmt"
	"path"
	"testing"
	"time"

	"cosmossdk.io/math"
	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/x/params/client/utils"
	transfertypes "github.com/cosmos/ibc-go/v7/modules/apps/transfer/types"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TransactionsTest(ctx context.Context, t *testing.T, chain Chain) {
	t.Run("Transactions", func(t *testing.T) {
		wallets, err := GetValidatorWallets(ctx, chain)
		require.NoError(t, err)
		wallet1 := wallets[0]
		wallet2 := wallets[1]
		valStake := "1000000000" + DENOM

		t.Run("bank send", func(t *testing.T) {
			// Send tokens from wallet1 to wallet2
			_, err = chain.Validators[0].ExecTx(
				ctx,
				wallet1.Moniker,
				"bank", "send", wallet1.Address, wallet2.Address, valStake,
			)
			require.NoError(t, err)
		})

		t.Run("delegate withdraw unbond", func(t *testing.T) {
			// delegate tokens
			_, err = chain.Validators[0].ExecTx(
				ctx,
				wallet1.Moniker,
				"staking", "delegate", wallet1.ValoperAddress, valStake,
			)
			require.NoError(t, err)

			startingBalance, err := chain.GetBalance(ctx, wallet1.Address, DENOM)
			require.NoError(t, err)
			time.Sleep(20 * time.Second)
			// Withdraw rewards
			_, err = chain.Validators[0].ExecTx(
				ctx,
				wallet1.Moniker,
				"distribution", "withdraw-rewards", wallet1.ValoperAddress,
			)
			require.NoError(t, err)
			endingBalance, err := chain.GetBalance(ctx, wallet1.Address, DENOM)
			require.NoError(t, err)
			require.Truef(t, endingBalance.GT(startingBalance), "endingBalance: %s, startingBalance: %s", endingBalance, startingBalance)

			// Unbond tokens
			_, err = chain.Validators[0].ExecTx(
				ctx,
				wallet1.Moniker,
				"staking", "unbond", wallet1.ValoperAddress, valStake,
			)
			require.NoError(t, err)
		})

		t.Run("authz", func(t *testing.T) {
			authzTest(ctx, t, chain)
		})

		t.Run("feegrant", func(t *testing.T) {
			feegrantTest(ctx, t, chain)
		})

		t.Run("multisig", func(t *testing.T) {
			multisigTest(ctx, t, chain)
		})
	})
}

func authzGenExec(ctx context.Context, t *testing.T, chain Chain, grantee ValidatorWallet, command ...string) error {
	txjson, err := chain.GenerateTx(ctx, 1, command...)
	require.NoError(t, err)

	err = chain.Validators[1].WriteFile(ctx, []byte(txjson), "tx.json")
	require.NoError(t, err)

	_, err = chain.Validators[1].ExecTx(
		ctx,
		grantee.Moniker,
		"authz", "exec", path.Join(chain.Validators[1].HomeDir(), "tx.json"),
	)
	return err
}

func authzTest(ctx context.Context, t *testing.T, chain Chain) {
	wallets, err := GetValidatorWallets(ctx, chain)
	require.NoError(t, err)
	amount := VALIDATOR_STAKE_STEP

	t.Run("send", func(t *testing.T) {
		balanceBefore, err := chain.GetBalance(ctx, wallets[2].Address, DENOM)
		require.NoError(t, err)
		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "grant", wallets[1].Address, "send",
			"--spend-limit", fmt.Sprintf("%d%s", amount*2, DENOM),
			"--allow-list", wallets[2].Address,
		)
		require.NoError(t, err)

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "bank", "send", wallets[0].Address, wallets[3].Address, fmt.Sprintf("%d%s", amount, DENOM)))

		require.NoError(t, authzGenExec(ctx, t, chain, wallets[1], "bank", "send", wallets[0].Address, wallets[2].Address, fmt.Sprintf("%d%s", amount, DENOM)))
		balanceAfter, err := chain.GetBalance(ctx, wallets[2].Address, DENOM)
		require.NoError(t, err)
		require.Equal(t, balanceBefore.Add(math.NewInt(int64(amount))), balanceAfter)

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "bank", "send", wallets[0].Address, wallets[2].Address, fmt.Sprintf("%d%s", amount+200, DENOM)))

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "revoke", wallets[1].Address, "/cosmos.bank.v1beta1.MsgSend",
		)
		require.NoError(t, err)

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "bank", "send", wallets[0].Address, wallets[2].Address, fmt.Sprintf("%d%s", amount, DENOM)))
	})

	t.Run("delegate", func(t *testing.T) {
		_, err := chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "grant", wallets[1].Address, "delegate",
			"--allowed-validators", wallets[2].ValoperAddress,
		)
		require.NoError(t, err)

		require.NoError(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "delegate", wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "delegate", wallets[0].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "revoke", wallets[1].Address, "/cosmos.staking.v1beta1.MsgDelegate",
		)
		require.NoError(t, err)
		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "delegate", wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))
	})

	t.Run("unbond", func(t *testing.T) {
		valHex, err := chain.GetValidatorHex(ctx, 2)
		require.NoError(t, err)
		powerBefore, err := GetPower(ctx, chain, valHex)
		require.NoError(t, err)
		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"staking", "delegate", wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM),
		)
		require.NoError(t, err)
		require.EventuallyWithT(t, func(c *assert.CollectT) {
			powerAfter, err := GetPower(ctx, chain, valHex)
			require.NoError(t, err)
			assert.NoError(c, err)
			assert.Greater(c, powerAfter, powerBefore)
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "grant", wallets[1].Address, "unbond",
			"--allowed-validators", wallets[2].ValoperAddress,
		)
		require.NoError(t, err)

		require.NoError(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "unbond", wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))
		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "unbond", wallets[0].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))

		require.EventuallyWithT(t, func(c *assert.CollectT) {
			powerAfter, err := GetPower(ctx, chain, valHex)
			require.NoError(t, err)
			assert.NoError(c, err)
			assert.Equal(c, powerAfter, powerBefore)
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "revoke", wallets[1].Address, "/cosmos.staking.v1beta1.MsgUndelegate",
		)
		require.NoError(t, err)
		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "unbond", wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))
	})

	t.Run("redelegate", func(t *testing.T) {
		val0Hex, err := chain.GetValidatorHex(ctx, 0)
		require.NoError(t, err)
		val2Hex, err := chain.GetValidatorHex(ctx, 2)
		require.NoError(t, err)
		val0PowerBefore, err := GetPower(ctx, chain, val0Hex)
		require.NoError(t, err)
		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"staking", "delegate", wallets[0].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM),
		)
		require.NoError(t, err)
		require.EventuallyWithT(t, func(c *assert.CollectT) {
			val0PowerAfter, err := GetPower(ctx, chain, val0Hex)
			require.NoError(t, err)
			assert.NoError(c, err)
			assert.Greater(c, val0PowerAfter, val0PowerBefore)
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "grant", wallets[1].Address, "redelegate",
			"--allowed-validators", wallets[2].ValoperAddress,
		)
		require.NoError(t, err)

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "redelegate", wallets[0].ValoperAddress, wallets[1].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))

		val2PowerBefore, err := GetPower(ctx, chain, val2Hex)
		require.NoError(t, err)
		require.NoError(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "redelegate", wallets[0].ValoperAddress, wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))
		require.EventuallyWithT(t, func(c *assert.CollectT) {
			val2PowerAfter, err := GetPower(ctx, chain, val2Hex)
			assert.NoError(c, err)
			assert.Greater(c, val2PowerAfter, val2PowerBefore)
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "revoke", wallets[1].Address, "/cosmos.staking.v1beta1.MsgBeginRedelegate",
		)
		require.NoError(t, err)

		require.Error(t, authzGenExec(ctx, t, chain, wallets[1], "staking", "redelegate", wallets[0].ValoperAddress, wallets[2].ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM), "--from", wallets[0].Address))
	})

	t.Run("generic", func(t *testing.T) {
		_, err := chain.Validators[0].ExecTx(
			ctx,
			wallets[0].Moniker,
			"authz", "grant", wallets[1].Address, "generic",
			"--msg-type", "/cosmos.gov.v1.MsgVote",
		)
		require.NoError(t, err)

		prop, err := chain.ParamChangeProposal(ctx, wallets[0].Moniker, &utils.ParamChangeProposalJSON{
			Title:       "Test Proposal",
			Description: "Test Proposal",
			Changes: utils.ParamChangesJSON{
				{
					Subspace: "staking",
					Key:      "MaxValidators",
					Value:    json.RawMessage(`100`),
				},
			},
			Deposit: GOV_DEPOSIT_AMOUNT,
		})
		require.NoError(t, err)
		require.NoError(t, authzGenExec(ctx, t, chain, wallets[1], "gov", "vote", prop.ProposalID, "yes", "--from", wallets[0].Address))
	})
}

func feegrantTest(ctx context.Context, t *testing.T, chain Chain) {
	wallets, err := GetValidatorWallets(ctx, chain)
	require.NoError(t, err)

	tests := []struct {
		name   string
		revoke func(expireTime time.Time)
	}{
		{
			name: "revoke",
			revoke: func(_ time.Time) {
				_, err := chain.Validators[0].ExecTx(
					ctx,
					wallets[0].Moniker,
					"feegrant", "revoke", wallets[0].Address, wallets[1].Address,
				)
				require.NoError(t, err)
			},
		},
		{
			name: "expire",
			revoke: func(expire time.Time) {
				<-time.After(time.Until(expire))
				err = testutil.WaitForBlocks(ctx, 1, chain)
				require.NoError(t, err)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			expire := time.Now().Add(20 * COMMIT_TIMEOUT)
			_, err = chain.Validators[0].ExecTx(
				ctx,
				wallets[0].Moniker,
				"feegrant", "grant", wallets[0].Address, wallets[1].Address,
				"--expiration", expire.Format(time.RFC3339),
			)
			require.NoError(t, err)

			balance0Before, err := chain.GetBalance(ctx, wallets[0].Address, DENOM)
			require.NoError(t, err)
			balance1Before, err := chain.GetBalance(ctx, wallets[1].Address, DENOM)
			require.NoError(t, err)

			_, err = chain.Validators[1].ExecTx(ctx, wallets[1].Moniker,
				"bank", "send", wallets[1].Address, wallets[2].Address, fmt.Sprintf("%d%s", VALIDATOR_STAKE_STEP, DENOM),
				"--fee-granter", wallets[0].Address,
			)
			require.NoError(t, err)

			balance0After, err := chain.GetBalance(ctx, wallets[0].Address, DENOM)
			require.NoError(t, err)
			balance1After, err := chain.GetBalance(ctx, wallets[1].Address, DENOM)
			require.NoError(t, err)

			require.True(t, balance0After.LT(balance0Before), "balance0After: %s, balance0Before: %s", balance0After, balance0Before)
			require.True(t, balance1After.Equal(balance1Before.Sub(math.NewInt(VALIDATOR_STAKE_STEP))))

			tt.revoke(expire)

			_, err = chain.Validators[1].ExecTx(ctx, wallets[1].Moniker,
				"bank", "send", wallets[1].Address, wallets[2].Address, fmt.Sprintf("%d%s", VALIDATOR_STAKE_STEP, DENOM),
				"--fee-granter", wallets[0].Address,
			)
			require.Error(t, err)
		})
	}
}

func multisigTest(ctx context.Context, t *testing.T, chain Chain) {
	wallets, err := GetValidatorWallets(ctx, chain)
	require.NoError(t, err)

	pubkey1, _, err := chain.Validators[1].ExecBin(ctx, "keys", "show", wallets[1].Moniker, "--pubkey", "--keyring-backend", "test")
	require.NoError(t, err)

	pubkey2, _, err := chain.Validators[2].ExecBin(ctx, "keys", "show", wallets[2].Moniker, "--pubkey", "--keyring-backend", "test")
	require.NoError(t, err)

	_, _, err = chain.Validators[0].ExecBin(ctx, "keys", "add", "val1", "--pubkey", string(pubkey1), "--keyring-backend", "test")
	require.NoError(t, err)

	_, _, err = chain.Validators[0].ExecBin(ctx, "keys", "add", "val2", "--pubkey", string(pubkey2), "--keyring-backend", "test")
	require.NoError(t, err)

	multisigName := "multisig"
	_, _, err = chain.Validators[0].ExecBin(ctx, "keys", "add", multisigName, "--multisig", fmt.Sprintf("%s,val1,val2", wallets[0].Moniker), "--multisig-threshold", "2", "--keyring-backend", "test")
	require.NoError(t, err)

	pubkeyMulti, _, err := chain.Validators[0].ExecBin(ctx, "keys", "show", multisigName, "--pubkey", "--keyring-backend", "test")
	require.NoError(t, err)

	_, _, err = chain.Validators[1].ExecBin(ctx, "keys", "add", multisigName, "--pubkey", string(pubkeyMulti), "--keyring-backend", "test")
	require.NoError(t, err)
	_, _, err = chain.Validators[2].ExecBin(ctx, "keys", "add", multisigName, "--pubkey", string(pubkeyMulti), "--keyring-backend", "test")
	require.NoError(t, err)
	// bogus validator, not in the multisig
	_, _, err = chain.Validators[4].ExecBin(ctx, "keys", "add", multisigName, "--pubkey", string(pubkeyMulti), "--keyring-backend", "test")
	require.NoError(t, err)

	defer func() {
		_, _, err = chain.Validators[0].ExecBin(ctx, "keys", "delete", "val1", "--keyring-backend", "test", "-y")
		require.NoError(t, err)
		_, _, err = chain.Validators[0].ExecBin(ctx, "keys", "delete", "val2", "--keyring-backend", "test", "-y")
		require.NoError(t, err)
		for i := 0; i < 3; i++ {
			_, _, err = chain.Validators[i].ExecBin(ctx, "keys", "delete", multisigName, "--keyring-backend", "test", "-y")
			require.NoError(t, err)
		}
		_, _, err = chain.Validators[4].ExecBin(ctx, "keys", "delete", multisigName, "--keyring-backend", "test", "-y")
		require.NoError(t, err)
	}()

	multisigAddr, err := chain.Validators[0].KeyBech32(ctx, multisigName, "")
	require.NoError(t, err)

	err = chain.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Denom:   DENOM,
		Amount:  sdkmath.NewInt(VALIDATOR_FUNDS),
		Address: multisigAddr,
	})
	require.NoError(t, err)

	balanceBefore, err := chain.GetBalance(ctx, wallets[3].Address, DENOM)
	require.NoError(t, err)

	txjson, err := chain.GenerateTx(ctx, 0, "bank", "send", multisigName, wallets[3].Address, fmt.Sprintf("%d%s", VALIDATOR_STAKE_STEP, DENOM), "--gas", "auto", "--gas-adjustment", "1.5", "--gas-prices", "0.025"+DENOM)
	require.NoError(t, err)

	err = chain.Validators[0].WriteFile(ctx, []byte(txjson), "tx.json")
	require.NoError(t, err)

	signed0, _, err := chain.Validators[0].Exec(ctx,
		chain.Validators[0].TxCommand(wallets[0].Moniker, "sign",
			path.Join(chain.Validators[0].HomeDir(), "tx.json"),
			"--multisig", multisigAddr,
		), nil)
	require.NoError(t, err)

	err = chain.Validators[1].WriteFile(ctx, []byte(txjson), "tx.json")
	require.NoError(t, err)

	signed1, _, err := chain.Validators[1].Exec(ctx,
		chain.Validators[1].TxCommand(wallets[1].Moniker, "sign",
			path.Join(chain.Validators[1].HomeDir(), "tx.json"),
			"--multisig", multisigAddr,
		), nil)
	require.NoError(t, err)

	err = chain.Validators[4].WriteFile(ctx, []byte(txjson), "tx.json")
	require.NoError(t, err)
	_, _, err = chain.Validators[4].Exec(ctx,
		chain.Validators[4].TxCommand(wallets[4].Moniker, "sign",
			path.Join(chain.Validators[4].HomeDir(), "tx.json"),
			"--multisig", multisigAddr,
		), nil)
	require.Error(t, err)

	err = chain.Validators[0].WriteFile(ctx, signed0, "signed0.json")
	require.NoError(t, err)

	_, _, err = chain.Validators[0].Exec(ctx, chain.Validators[0].TxCommand(
		multisigName,
		"multisign",
		path.Join(chain.Validators[0].HomeDir(), "tx.json"),
		multisigName,
		path.Join(chain.Validators[0].HomeDir(), "signed0.json"),
	), nil)
	require.NoError(t, err)

	err = chain.Validators[0].WriteFile(ctx, signed1, "signed1.json")
	require.NoError(t, err)

	multisign, _, err := chain.Validators[0].Exec(ctx, chain.Validators[0].TxCommand(
		multisigName,
		"multisign",
		path.Join(chain.Validators[0].HomeDir(), "tx.json"),
		multisigName,
		path.Join(chain.Validators[0].HomeDir(), "signed0.json"),
		path.Join(chain.Validators[0].HomeDir(), "signed1.json"),
	), nil)
	require.NoError(t, err)

	err = chain.Validators[0].WriteFile(ctx, multisign, "multisign.json")
	require.NoError(t, err)

	_, err = chain.Validators[0].ExecTx(ctx, multisigName, "broadcast", path.Join(chain.Validators[0].HomeDir(), "multisign.json"))
	require.NoError(t, err)
	balanceAfter, err := chain.GetBalance(ctx, wallets[3].Address, DENOM)
	require.NoError(t, err)
	require.Equal(t, balanceBefore.Add(math.NewInt(VALIDATOR_STAKE_STEP)), balanceAfter)
}

func IBCTest(ctx context.Context, t *testing.T, chainA Chain, chainB Chain, relayer ibc.Relayer) {
	wallets, err := GetValidatorWallets(ctx, chainA)
	require.NoError(t, err)
	wallet1 := wallets[0]

	wallets, err = GetValidatorWallets(ctx, chainB)
	require.NoError(t, err)
	wallet2 := wallets[0]
	addr1 := wallet1.Address
	addr2 := wallet2.Address

	senderTxChannel, err := GetTransferChannel(ctx, relayer, chainA, chainB)
	require.NoError(t, err)

	srcDenomTrace := transfertypes.ParseDenomTrace(transfertypes.GetPrefixedDenom("transfer", senderTxChannel.Counterparty.ChannelID, chainA.Config().Denom))
	dstIbcDenom := srcDenomTrace.IBCDenom()

	initial1, err := chainA.GetBalance(ctx, addr1, chainA.Config().Denom)
	require.NoError(t, err)
	initial2, err := chainB.GetBalance(ctx, addr2, dstIbcDenom)
	require.NoError(t, err)

	amountToSend := math.NewInt(1_000_000)
	_, err = chainA.Validators[0].SendIBCTransfer(ctx, senderTxChannel.ChannelID, wallet1.Moniker, ibc.WalletAmount{
		Denom:   chainA.Config().Denom,
		Amount:  amountToSend,
		Address: addr2,
	}, ibc.TransferOptions{})
	require.NoError(t, err)

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		final1, err := chainA.GetBalance(ctx, addr1, chainA.Config().Denom)
		assert.NoError(c, err)
		final2, err := chainB.GetBalance(ctx, addr2, dstIbcDenom)
		assert.NoError(c, err)

		assert.Equal(c, initial2.Add(amountToSend), final2)
		assert.True(c, final1.LTE(initial1.Sub(amountToSend)), "final1: %s, initial1 - amountToSend: %s", final1, initial1.Sub(amountToSend))
	}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
}
