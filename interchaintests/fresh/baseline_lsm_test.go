package fresh_test

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

// func setStrideParams(ctx context.Context, t *testing.T, stride fresh.Chain, change utils.ParamChangeJSON) {
// 	result, err := stride.ParamChangeProposal(ctx, fresh.VALIDATOR_MONIKER, &utils.ParamChangeProposalJSON{
// 		Changes:     []utils.ParamChangeJSON{change},
// 		Title:       fmt.Sprintf("%s -> %s", change.Key, change.Value),
// 		Description: fmt.Sprintf("Change %s to %s", change.Key, change.Value),
// 		Deposit:     fresh.GOV_DEPOSIT_AMOUNT,
// 	})
// 	require.NoError(t, err)
// 	fresh.PassProposal(ctx, t, stride, result.ProposalID)
// }

func setupICA(ctx context.Context, t *testing.T, provider, stride fresh.Chain, relayer ibc.Relayer) string {
	wallets, err := fresh.GetValidatorWallets(ctx, stride)
	require.NoError(t, err)
	srcAddress := wallets[0].Address
	channel, err := fresh.GetChannelWithPort(ctx, relayer, stride, provider, fresh.CONSUMER_PORT_ID)
	require.NoError(t, err)
	_, err = stride.Validators[0].ExecTx(ctx, srcAddress,
		"interchain-accounts", "controller", "register",
		channel.ConnectionHops[0], "--gas", "auto",
	)
	require.NoError(t, err)
	icaAddress := fresh.GetICAAddress(ctx, t, stride, srcAddress, channel.ConnectionHops[0])
	require.NotEmpty(t, icaAddress)
	err = provider.SendFunds(ctx, fresh.VALIDATOR_MONIKER, ibc.WalletAmount{
		Amount:  sdkmath.NewInt(1_000_000_000),
		Denom:   fresh.DENOM,
		Address: icaAddress,
	})
	require.NoError(t, err)
	return icaAddress
}

func lsmAccountSetup(ctx context.Context, t *testing.T, provider fresh.Chain) map[string]ibc.Wallet {
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
			return provider.SendFunds(ctx, fresh.VALIDATOR_MONIKER, ibc.WalletAmount{
				Amount:  sdkmath.NewInt(int64(amount)),
				Denom:   fresh.DENOM,
				Address: wallet.FormattedAddress(),
			})
		})
	}
	require.NoError(t, eg.Wait())
	return wallets
}

func checkAMinusBEqualsX(t *testing.T, a, b string, x int64) {
	t.Helper()
	// trim the .00s from the string
	a, _, _ = strings.Cut(a, ".")
	b, _, _ = strings.Cut(b, ".")
	intA, ok := sdkmath.NewIntFromString(a)
	require.Truef(t, ok, "a: %s", a)
	intB, ok := sdkmath.NewIntFromString(b)
	require.Truef(t, ok, "b: %s", b)
	require.Equal(t, x, intA.Sub(intB).Int64())
}

func testLSMHappyPath(ctx context.Context, t *testing.T, provider, stride fresh.Chain, relayer ibc.Relayer, lsmWallets map[string]ibc.Wallet) {
	const (
		delegation    = 100000000
		tokenize      = 50000000
		bankSend      = 20000000
		ibcTransfer   = 10000000
		liquid1Redeem = 20000000
	)
	providerWallets, err := fresh.GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerWallet := providerWallets[0]

	strideWallets, err := fresh.GetValidatorWallets(ctx, stride)
	require.NoError(t, err)
	strideWallet := strideWallets[0]

	t.Run("Validator Bond", func(t *testing.T) {
		delegatorShares1 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		validatorBondShares1 := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["bonding"].FormattedAddress(),
			"staking", "delegate", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, fresh.DENOM))
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
			"staking", "delegate", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, fresh.DENOM))
		require.NoError(t, err)
		delegatorShares2 := provider.QueryJSON(ctx, t, "delegator_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, delegatorShares2, delegatorShares1, delegation)

		sharesPreTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "tokenize-share",
			providerWallet.ValoperAddress, fmt.Sprintf("%d%s", tokenize, fresh.DENOM), lsmWallets["liquid_1"].FormattedAddress(),
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

	ibcChannelProvider, err := fresh.GetTransferChannel(ctx, relayer, provider, stride)
	require.NoError(t, err)
	ibcChannelStride, err := fresh.GetTransferChannel(ctx, relayer, stride, provider)
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
		fmt.Print(happyLiquid1Delegations1)
		_, err := provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", liquid1Redeem, tokenizedDenom))
		require.NoError(t, err)

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_2"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", bankSend, tokenizedDenom))
		require.NoError(t, err)

		_, err = stride.SendIBCTransfer(ctx, ibcChannelStride.ChannelID, strideWallet.Address, ibc.WalletAmount{
			Amount:  sdkmath.NewInt(ibcTransfer),
			Denom:   ibcDenom,
			Address: lsmWallets["liquid_3"].FormattedAddress(),
		}, ibc.TransferOptions{})
		require.NoError(t, err)

		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_3"].FormattedAddress(),
			"staking", "redeem-tokens", fmt.Sprintf("%d%s", ibcTransfer, tokenizedDenom))
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
		// echo "Validator unbond from happy_bonding"
		// # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-1 $happy_bonding $delegation
		// submit_tx "tx staking unbond $VALOPER_1 100000000$DENOM --from $happy_bonding -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
		_, err := provider.GetNode().ExecTx(ctx, lsmWallets["bonding"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", delegation, fresh.DENOM))
		require.NoError(t, err)
		// # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-1 $happy_bonding $delegation

		// validator_bond_shares=$($CHAIN_BINARY q staking validator $VALOPER_1 --home $HOME_1 -o json | jq -r '.validator_bond_shares')
		validatorBondShares := provider.QueryJSON(ctx, t, "validator_bond_shares", "staking", "validator", providerWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, validatorBondShares, "0", 0)
		// echo "Validator bond shares: ${validator_bond_shares%.*}"
		// if [[ ${validator_bond_shares%.*} -ne 0  ]]; then
		// 	echo "Unbond unsuccessful: unexpected validator bond shares amount"
		// 	exit 1
		// fi

		// echo "Validator unbond from happy_liquid_1..."
		// # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-2 $happy_liquid_1 $happy_liquid_1_delegation_balance
		// submit_tx "tx staking unbond $VALOPER_1 $happy_liquid_1_delegation_balance$DENOM --from $happy_liquid_1 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_1"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%s%s", happyLiquid1DelegationBalance, fresh.DENOM))
		require.NoError(t, err)
		// # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-2 $happy_liquid_1 70000000

		// echo "Validator unbond from happy_liquid_2..."
		// # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-3 $happy_liquid_2 $bank_send_amount
		// submit_tx "tx staking unbond $VALOPER_1 $bank_send_amount$DENOM --from $happy_liquid_2 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_2"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", bankSend, fresh.DENOM))
		require.NoError(t, err)
		// # tests/v12_upgrade/log_lsm_data.sh happy post-unbond-3 $happy_liquid_2 $bank_send_amount

		// echo "Validator unbond from happy_liquid_3..."
		// # tests/v12_upgrade/log_lsm_data.sh happy pre-unbond-4 $happy_liquid_3 $ibc_transfer_amount
		// submit_tx "tx staking unbond $VALOPER_1 $ibc_transfer_amount$DENOM --from $happy_liquid_3 -o json --gas auto --gas-adjustment $GAS_ADJUSTMENT -y --gas-prices $GAS_PRICE$DENOM" $CHAIN_BINARY $HOME_1
		_, err = provider.GetNode().ExecTx(ctx, lsmWallets["liquid_3"].FormattedAddress(),
			"staking", "unbond", providerWallet.ValoperAddress, fmt.Sprintf("%d%s", ibcTransfer, fresh.DENOM))
		require.NoError(t, err)
	})
}

func TestLSMWithV16Upgrade(t *testing.T) {
	t.Skip("WIP test")
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, relayer := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	stride := fresh.AddConsumerChain(ctx, t, provider, relayer, "stride", "v20.0.0", fresh.STRIDE_DENOM, []bool{false, false, false})

	// fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, relayer)
	// fresh.IBCTest(ctx, t, provider, stride, relayer)

	lsmWallets := lsmAccountSetup(ctx, t, provider)

	// setStrideParams(ctx, t, provider, utils.ParamChangeJSON{
	// 	Subspace: "staking",
	// 	Key:      "GlobalLiquidStakingCap",
	// 	Value:    json.RawMessage("0.1"),
	// })
	// setStrideParams(ctx, t, provider, utils.ParamChangeJSON{
	// 	Subspace: "staking",
	// 	Key:      "ValidatorLiquidStakingCap",
	// 	Value:    json.RawMessage("0.2"),
	// })
	// setStrideParams(ctx, t, provider, utils.ParamChangeJSON{
	// 	Subspace: "staking",
	// 	Key:      "ValidatorBondFactor",
	// 	Value:    json.RawMessage("10.00"),
	// })

	testLSMHappyPath(ctx, t, provider, stride, relayer, lsmWallets)

	setupICA(ctx, t, provider, stride, relayer)
}

func tokenizeVestedTest(ctx context.Context, t *testing.T, provider fresh.Chain, isUpgraded bool) {
	// gaiad tx vesting create-vesting-account <cosmos address> 100000000uatom <vesting target in epoch format>
	const amount = 100_000_000_000
	const vestingPeriod = 100 * time.Second
	vestedByTimestamp := time.Now().Add(vestingPeriod).Unix()
	vestingAccount, err := provider.BuildWallet(ctx, fmt.Sprintf("vesting-%d", vestedByTimestamp), "")
	require.NoError(t, err)
	wallets, err := fresh.GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	validatorWallet := wallets[0]

	_, err = provider.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"vesting", "create-vesting-account", vestingAccount.FormattedAddress(),
		fmt.Sprintf("%d%s", amount, fresh.DENOM),
		fmt.Sprintf("%d", vestedByTimestamp))
	require.NoError(t, err)

	// give the vesting account a little cash for gas fees
	err = provider.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Amount:  sdkmath.NewInt(5_000),
		Denom:   fresh.DENOM,
		Address: vestingAccount.FormattedAddress(),
	})
	require.NoError(t, err)

	vestingAmount := int64(amount - 1000)
	// delegate the vesting account to the validator
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "delegate", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount, fresh.DENOM))
	require.NoError(t, err)

	// wait for half the vesting period
	time.Sleep(vestingPeriod / 2)

	// try to tokenize full amount. Should fail.
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "tokenize-share", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount, fresh.DENOM), vestingAccount.FormattedAddress(),
		"--gas", "auto")
	require.Error(t, err)

	sharesPreTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", validatorWallet.ValoperAddress).String()

	// try to tokenize vested amount (i.e. half) should succeed if upgraded
	_, err = provider.GetNode().ExecTx(ctx, vestingAccount.FormattedAddress(),
		"staking", "tokenize-share", validatorWallet.ValoperAddress, fmt.Sprintf("%d%s", vestingAmount/2, fresh.DENOM), vestingAccount.FormattedAddress(),
		"--gas", "auto")
	if isUpgraded {
		require.NoError(t, err)
		sharesPostTokenize := provider.QueryJSON(ctx, t, "liquid_shares", "staking", "validator", validatorWallet.ValoperAddress).String()
		checkAMinusBEqualsX(t, sharesPostTokenize, sharesPreTokenize, vestingAmount/2)

	} else {
		require.Error(t, err)
	}
}

func TestLSMTokenizeVestedAfterV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, _ := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)
	// fresh.AddConsumerChain(ctx, t, provider, relayer, "stride", "v20.0.0", fresh.STRIDE_DENOM, []bool{false, false, false})

	tokenizeVestedTest(ctx, t, provider, false)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	tokenizeVestedTest(ctx, t, provider, true)
}
