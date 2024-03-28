package fresh

import (
	"context"
	"testing"
	"time"

	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/stretchr/testify/require"
)

func TransactionsTest(ctx context.Context, t *testing.T, chain *cosmos.CosmosChain) {
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
