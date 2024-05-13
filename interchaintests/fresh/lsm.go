package fresh

import (
	"context"
	"encoding/json"
	"fmt"
	"path"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

func LSMAccountSetup(ctx context.Context, t *testing.T, provider Chain) map[string]ibc.Wallet {
	names := []string{"bonding", "liquid_1", "liquid_2", "liquid_3", "owner"}
	wallets := make(map[string]ibc.Wallet)
	eg := new(errgroup.Group)
	for _, name := range names {
		keyName := "happy_" + name
		wallet, err := provider.BuildWallet(ctx, keyName, "")
		require.NoError(t, err)
		wallets[name] = wallet
		amount := 500_000_000
		if name == "owner" {
			amount = 10_000_000
		}
		eg.Go(func() error {
			return provider.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
				Amount:  sdkmath.NewInt(int64(amount)),
				Denom:   DENOM,
				Address: wallet.FormattedAddress(),
			})
		})
	}
	require.NoError(t, eg.Wait())
	return wallets
}

func LSMHappyPathTest(ctx context.Context, t *testing.T, provider, stride Chain, relayer ibc.Relayer, lsmWallets map[string]ibc.Wallet) {
	const (
		delegation    = 100000000
		tokenize      = 50000000
		bankSend      = 20000000
		ibcTransfer   = 10000000
		liquid1Redeem = 20000000
	)
	providerWallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerWallet := providerWallets[0]

	strideWallets, err := GetValidatorWallets(ctx, stride)
	require.NoError(t, err)
	strideWallet := strideWallets[0]

	t.Run("Validator Bond", func(t *testing.T) {
		delegatorShares1 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		validatorBondShares1 := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["bonding"].FormattedAddress(),
			"staking", "delegate", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, DENOM))
		require.NoError(t, err)
		delegatorShares2 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, delegatorShares2, delegatorShares1, delegation)

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["bonding"].FormattedAddress(),
			"staking", "validator-bond", providerWallet.ValoperAddress)
		require.NoError(t, err)
		validatorBondShares2 := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, validatorBondShares2, validatorBondShares1, delegation)
	})

	var tokenizedDenom string
	t.Run("Tokenize", func(t *testing.T) {
		delegatorShares1 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		_, err := provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "delegate", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, DENOM))
		require.NoError(t, err)
		delegatorShares2 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, delegatorShares2, delegatorShares1, delegation)

		sharesPreTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "tokenize-share",
			providerWallet.ValoperAddress, fmt.Sprintf("%d%s", tokenize, DENOM), lsmWallets["liquid_1"].FormattedAddress(),
			"--gas", "auto")
		require.NoError(t, err)
		sharesPostTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, sharesPostTokenize, sharesPreTokenize, tokenize)

		balances, err := provider.AllBalances(ctx, lsmWallets["liquid_1"].FormattedAddress())
		require.NoError(t, err)
		for _, balance := range balances {
			if balance.Amount.Int64() == tokenize {
				tokenizedDenom = balance.Denom
			}
		}
		require.NotEmpty(t, tokenizedDenom)
	})

	t.Run("Transfer Ownership", func(t *testing.T) {
		recordID := provider.QueryJSON(ctx, t, "record.id", "staking", "tokenize-share-record-by-denom", tokenizedDenom).String()
		owner := provider.QueryJSON(ctx, t, "record.owner", "staking", "tokenize-share-record-by-denom", tokenizedDenom).String()

		_, err := provider.GetNode().ExecTx(ctx, owner,
			"staking", "transfer-tokenize-share-record", recordID, lsmWallets["owner"].FormattedAddress())
		require.NoError(t, err)

		owner = provider.QueryJSON(ctx, t, "record.owner", "staking", "tokenize-share-record-by-denom", tokenizedDenom).String()
		require.Equal(t, lsmWallets["owner"].FormattedAddress(), owner)

		_, err = provider.GetNode().ExecTx(ctx, owner,
			"staking", "transfer-tokenize-share-record", recordID, lsmWallets["liquid_1"].FormattedAddress())
		require.NoError(t, err)

		owner = provider.QueryJSON(ctx, t, "record.owner", "staking", "tokenize-share-record-by-denom", tokenizedDenom).String()
		require.Equal(t, lsmWallets["liquid_1"].FormattedAddress(), owner)
	})

	var happyLiquid1Delegations1 string
	var ibcDenom string

	ibcChannelProvider, err := GetTransferChannel(ctx, relayer, provider, stride)
	require.NoError(t, err)
	ibcChannelStride, err := GetTransferChannel(ctx, relayer, stride, provider)
	require.NoError(t, err)

	t.Run("Transfer Tokens", func(t *testing.T) {
		happyLiquid1Delegations1 = provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").delegation.shares", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_1"].FormattedAddress()).String()

		err := provider.SendFunds(ctx, lsmWallets["liquid_1"].FormattedAddress(), ibc.WalletAmount{
			Amount:  sdkmath.NewInt(bankSend),
			Denom:   tokenizedDenom,
			Address: lsmWallets["liquid_2"].FormattedAddress(),
		})
		require.NoError(t, err)

		_, err = provider.SendIBCTransfer(ctx, ibcChannelProvider.ChannelID, lsmWallets["liquid_1"].FormattedAddress(), ibc.WalletAmount{
			Amount:  sdkmath.NewInt(ibcTransfer),
			Denom:   tokenizedDenom,
			Address: strideWallet.Address,
		}, ibc.TransferOptions{})
		require.NoError(t, err)
		require.NoError(t, testutil.WaitForBlocks(ctx, 5, stride))
		balances, err := stride.AllBalances(ctx, strideWallet.Address)
		require.NoError(t, err)
		for _, balance := range balances {
			if balance.Amount.Int64() == ibcTransfer {
				ibcDenom = balance.Denom
			}
		}
		require.NotEmpty(t, ibcDenom)
	})

	var happyLiquid1DelegationBalance string
	t.Run("Redeem Tokens", func(t *testing.T) {
		_, err := provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", liquid1Redeem, tokenizedDenom),
			"--gas", "auto")
		require.NoError(t, err)

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_2"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", bankSend, tokenizedDenom),
			"--gas", "auto")
		require.NoError(t, err)

		_, err = stride.SendIBCTransfer(ctx, ibcChannelStride.ChannelID, strideWallet.Address, ibc.WalletAmount{
			Amount:  sdkmath.NewInt(ibcTransfer),
			Denom:   ibcDenom,
			Address: lsmWallets["liquid_3"].FormattedAddress(),
		}, ibc.TransferOptions{})
		require.NoError(t, err)
		// wait for the transfer to be reflected
		require.NoError(t, testutil.WaitForBlocks(ctx, 5, provider))

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_3"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", ibcTransfer, tokenizedDenom),
			"--gas", "auto")
		require.NoError(t, err)

		happyLiquid1Delegations2 := provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").delegation.shares", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_1"].FormattedAddress()).String()
		checkAMinusBEqualsX(t, happyLiquid1Delegations2, happyLiquid1Delegations1, liquid1Redeem)

		happyLiquid2Delegations := provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").delegation.shares", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_2"].FormattedAddress()).String()
		// LOL there are better ways of doing this
		checkAMinusBEqualsX(t, happyLiquid2Delegations, "0", bankSend)
		happyLiquid3Delegations := provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").delegation.shares", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_3"].FormattedAddress()).String()
		checkAMinusBEqualsX(t, happyLiquid3Delegations, "0", ibcTransfer)

		happyLiquid1DelegationBalance = provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").balance.amount", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_1"].FormattedAddress()).String()
		happyLiquid2DelegationBalance := provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").balance.amount", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_2"].FormattedAddress()).String()
		happyLiquid3DelegationBalance := provider.QueryJSON(ctx, t, fmt.Sprintf("delegation_responses.#(delegation.validator_address==\"%s\").balance.amount", providerWallet.ValoperAddress), "staking", "delegations", lsmWallets["liquid_3"].FormattedAddress()).String()
		checkAMinusBEqualsX(t, happyLiquid1DelegationBalance, "0", 70000000)
		checkAMinusBEqualsX(t, happyLiquid2DelegationBalance, "0", bankSend)
		checkAMinusBEqualsX(t, happyLiquid3DelegationBalance, "0", ibcTransfer)
	})
	t.Run("Cleanup", func(t *testing.T) {
		_, err := provider.GetNode().ExecTx(ctx, lsmWallets["bonding"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, DENOM))
		require.NoError(t, err)

		validatorBondShares := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, validatorBondShares, "0", 0)

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%s%s", happyLiquid1DelegationBalance, DENOM))
		require.NoError(t, err)
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_2"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", bankSend, DENOM))
		require.NoError(t, err)
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_3"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", ibcTransfer, DENOM))
		require.NoError(t, err)
	})
}

func ICADelegateHappyPathTest(ctx context.Context, t *testing.T, provider, stride Chain, relayer ibc.Relayer, icaAddress string) {
	const (
		delegate       = 20000000
		bondDelegation = 20000000
	)
	bondingWallet, err := provider.BuildWallet(ctx, fmt.Sprintf("lsp_happy_bonding_%d", time.Now().Unix()), "")
	require.NoError(t, err)

	err = provider.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Amount:  sdkmath.NewInt(50_000_000),
		Denom:   DENOM,
		Address: bondingWallet.FormattedAddress(),
	})
	require.NoError(t, err)

	providerWallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerWallet := providerWallets[1]

	strideWallets, err := GetValidatorWallets(ctx, stride)
	require.NoError(t, err)
	strideWallet := strideWallets[0]

	t.Run("Delegate and Bond", func(t *testing.T) {
		shares1 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		tokens1 := provider.QueryJSON(ctx, t, "tokens", "staking", "validator", providerWallet.ValoperAddress).String()
		bondShares1 := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		shares1Int := strToSDKInt(t, shares1)
		tokens1Int := strToSDKInt(t, tokens1)
		bondShares1Int := strToSDKInt(t, bondShares1)

		exchangeRate1 := shares1Int.Quo(tokens1Int)
		expectedSharesIncrease := exchangeRate1.MulRaw(bondDelegation)
		expectedShares := expectedSharesIncrease.Add(bondShares1Int)

		_, err := provider.GetNode().ExecTx(ctx, bondingWallet.FormattedAddress(),
			"staking", "delegate", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", bondDelegation, DENOM))
		require.NoError(t, err)

		_, err = provider.GetNode().ExecTx(ctx, bondingWallet.FormattedAddress(),
			"staking", "validator-bond", providerWallet.ValoperAddress)
		require.NoError(t, err)

		bondShares2 := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		bondShares2Int := strToSDKInt(t, bondShares2)
		require.Truef(t, bondShares2Int.Sub(expectedShares).Abs().LTE(sdkmath.NewInt(1)), "bondShares2: %s, expectedShares: %s", bondShares2, expectedShares)
	})

	t.Run("Delegate via ICA", func(t *testing.T) {
		preDelegationTokens := provider.QueryJSON(ctx, t, "tokens", "staking", "validator", providerWallet.ValoperAddress).String()
		preDelegationShares := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		preDelegationLiquidShares := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", providerWallet.ValoperAddress).String()

		preDelegationTokensInt := strToSDKInt(t, preDelegationTokens)
		preDelegationSharesInt := strToSDKInt(t, preDelegationShares)
		exchangeRate := preDelegationSharesInt.Quo(preDelegationTokensInt)
		expectedLiquidIncrease := exchangeRate.MulRaw(delegate)

		delegateHappy := map[string]interface{}{
			"@type":             "/cosmos.staking.v1beta1.MsgDelegate",
			"delegator_address": icaAddress,
			"validator_address": providerWallet.ValoperAddress,
			"amount": map[string]interface{}{
				"denom":  DENOM,
				"amount": fmt.Sprint(delegate),
			},
		}
		delegateHappyJSON, err := json.Marshal(delegateHappy)
		require.NoError(t, err)
		jsonPath := "delegate-happy.json"
		fullJsonPath := path.Join(stride.Validators[0].HomeDir(), jsonPath)
		stdout, _, err := stride.GetNode().ExecBin(ctx, "tx", "interchain-accounts", "host", "generate-packet-data", string(delegateHappyJSON), "--encoding", "proto3")
		require.NoError(t, err)
		require.NoError(t, stride.Validators[0].WriteFile(ctx, []byte(stdout), jsonPath))
		ibcChannelStride, err := GetTransferChannel(ctx, relayer, stride, provider)
		require.NoError(t, err)

		_, err = stride.GetNode().ExecTx(ctx, strideWallet.Address,
			"interchain-accounts", "controller", "send-tx", ibcChannelStride.ConnectionHops[0], fullJsonPath)
		require.NoError(t, err)

		var tokensDelta sdkmath.Int
		require.EventuallyWithT(t, func(c *assert.CollectT) {
			postDelegationTokens := provider.QueryJSON(ctx, t, "tokens", "staking", "validator", providerWallet.ValoperAddress).String()
			tokensDelta = strToSDKInt(t, postDelegationTokens).Sub(strToSDKInt(t, preDelegationTokens))
			assert.Truef(c, tokensDelta.Sub(sdkmath.NewInt(delegate)).Abs().LTE(sdkmath.NewInt(1)), "tokensDelta: %s, delegate: %d", tokensDelta, delegate)
		}, 20*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

		postDelegationLiquidShares := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		liquidSharesDelta := strToSDKInt(t, postDelegationLiquidShares).Sub(strToSDKInt(t, preDelegationLiquidShares))
		require.Truef(t, liquidSharesDelta.Sub(expectedLiquidIncrease).Abs().LTE(sdkmath.NewInt(1)), "liquidSharesDelta: %s, expectedLiquidIncrease: %d", liquidSharesDelta, expectedLiquidIncrease)
	})
}

func TokenizeVestedAmountTest(ctx context.Context, t *testing.T, provider Chain, isUpgraded bool) {
	const amount = 100_000_000_000
	const vestingPeriod = 100 * time.Second
	vestedByTimestamp := time.Now().Add(vestingPeriod).Unix()
	vestingAccount, err := provider.BuildWallet(ctx, fmt.Sprintf("vesting-%d", vestedByTimestamp), "")
	require.NoError(t, err)
	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	validatorWallet := wallets[0]

	_, err = provider.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"vesting", "create-vesting-account", vestingAccount.FormattedAddress(),
		fmt.Sprintf("%d%s", amount, DENOM),
		fmt.Sprintf("%d", vestedByTimestamp))
	require.NoError(t, err)

	// give the vesting account a little cash for gas fees
	err = provider.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Amount:  sdkmath.NewInt(5_000),
		Denom:   DENOM,
		Address: vestingAccount.FormattedAddress(),
	})
	require.NoError(t, err)

	vestingAmount := int64(amount - 1000)
	// delegate the vesting account to the validator
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "delegate", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount, DENOM))
	require.NoError(t, err)

	// wait for half the vesting period
	time.Sleep(vestingPeriod / 2)

	// try to tokenize full amount. Should fail.
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "tokenize-share", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount, DENOM), vestingAccount.FormattedAddress(),
		"--gas", "auto")
	require.Error(t, err)

	sharesPreTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", validatorWallet.ValoperAddress).String()

	// try to tokenize vested amount (i.e. half) should succeed if upgraded
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "tokenize-share", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount/2, DENOM), vestingAccount.FormattedAddress(),
		"--gas", "auto")
	if isUpgraded {
		require.NoError(t, err)
		sharesPostTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", validatorWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, sharesPostTokenize, sharesPreTokenize, vestingAmount/2)

	} else {
		require.Error(t, err)
	}
}
