package fresh

import (
	"context"
	"testing"
	"time"

	"cosmossdk.io/math"
	transfertypes "github.com/cosmos/ibc-go/v7/modules/apps/transfer/types"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
)

func TransactionsTest(ctx context.Context, t *testing.T, chain Chain) {
	t.Run("Transactions", func(t *testing.T) {
		wallets, err := GetValidatorWallets(ctx, chain)
		require.NoError(t, err)
		wallet1 := wallets[0]
		wallet2 := wallets[1]
		valStake := "1000000000" + DENOM

		// Send tokens from wallet1 to wallet2
		// note that this checks the code.
		_, err = chain.Validators[0].ExecTx(
			ctx,
			wallet1.Moniker,
			"bank", "send", wallet1.Address, wallet2.Address, valStake,
		)
		require.NoError(t, err)

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

	res := relayer.Exec(ctx, GetRelayerExecReporter(ctx), []string{
		"hermes", "clear", "packets", "--chain", chainA.Config().ChainID, "--channel", senderTxChannel.ChannelID, "--port", "transfer",
	}, nil)
	require.NoError(t, res.Err)

	final1, err := chainA.GetBalance(ctx, addr1, chainA.Config().Denom)
	require.NoError(t, err)
	final2, err := chainB.GetBalance(ctx, addr2, dstIbcDenom)
	require.NoError(t, err)

	require.Equal(t, initial2.Add(amountToSend), final2)
	require.True(t, final1.LTE(initial1.Sub(amountToSend)), "final1: %s, initial1 - amountToSend: %s", final1, initial1.Sub(amountToSend))
}
