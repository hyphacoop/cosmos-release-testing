package fresh_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	transfertypes "github.com/cosmos/ibc-go/v8/modules/apps/transfer/types"
	providertypes "github.com/cosmos/interchain-security/v5/x/ccv/provider/types"
	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v8/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v8/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

type whenToOptIn struct {
	Name string
	Set  func(*fresh.ConsumerConfig, fresh.ConsumerBootstrapCb)
}

var optInDuringDeposit = &whenToOptIn{
	Name: "deposit",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.DuringDepositPeriod = bootstrapCb
	},
}

var optInDuringVoting = &whenToOptIn{
	Name: "voting",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.DuringVotingPeriod = bootstrapCb
	},
}

var optInBeforeSpawn = &whenToOptIn{
	Name: "before spawn",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.BeforeSpawnTime = bootstrapCb
	},
}

var optInAfterSpawn = &whenToOptIn{
	Name: "after spawn",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.AfterSpawnTime = bootstrapCb
	},
}

var optInTimes = []*whenToOptIn{optInDuringDeposit, optInDuringVoting, optInBeforeSpawn, optInAfterSpawn}

func optInFunction(t *testing.T, provider fresh.Chain, validators ...int) func(context.Context, *cosmos.CosmosChain) {
	return func(ctx context.Context, consumer *cosmos.CosmosChain) {
		consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
		eg := errgroup.Group{}
		for _, i := range validators {
			i := i
			eg.Go(func() error {
				_, err := provider.Validators[i].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
					"provider", "opt-in", consumerID)
				return err
			})
		}
		require.NoError(t, eg.Wait())
	}
}

func getConsumerConfig(topN int, whenToOptIn *whenToOptIn, howToOptIn fresh.ConsumerBootstrapCb) fresh.ConsumerConfig {
	consumerConfig := fresh.ConsumerConfig{
		TopN:                  topN,
		ChainName:             "ics-consumer",
		Version:               "v4.4.0",
		Denom:                 fresh.CONSUMER_DENOM,
		ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
	}
	if whenToOptIn != nil && howToOptIn != nil {
		whenToOptIn.Set(&consumerConfig, howToOptIn)
	}
	return consumerConfig
}

func TestPSSChainLaunchAfterUpgradeTop80(t *testing.T) {
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			const optInVal = 4

			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			optIn := optInFunction(t, provider, optInVal)

			consumerConfig := getConsumerConfig(80, optInTime, optIn)
			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			// opted in automatically
			for i := 1; i < 4; i++ {
				fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, i, true)
			}
			// // did not opt in
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 5, false)

			consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, true)
			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumerID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, false)

			_, err = provider.Validators[3].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumerID)
			require.Error(t, err)

			// kick a validator out of the top 80, and push a different one in
			// wallets, err := fresh.GetValidatorWallets(ctx, provider)
			// require.NoError(t, err)
			fresh.DelegateToValidator(ctx, t, provider, consumer, 20*fresh.VALIDATOR_STAKE_STEP, 5, 1)
			// _, err = provider.Validators[5].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
			// 	"staking", "delegate", wallets[5].ValoperAddress, fmt.Sprintf("%d%s", 20*fresh.VALIDATOR_STAKE_STEP, fresh.DENOM))
			// require.NoError(t, err)
			// require.NoError(t, testutil.WaitForBlocks(ctx, 10, consumer))

			_, err = provider.Validators[3].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumerID)
			require.NoError(t, err)

			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 5, true)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 3, false)
		})
	}
}

func TestPSSChainLaunchAfterUpgradeTop67(t *testing.T) {
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			const optInVal = 5

			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			optIn := optInFunction(t, provider, optInVal)

			consumerConfig := getConsumerConfig(67, optInTime, optIn)
			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			// opted in automatically
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 2, true)
			// did not opt in
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 3, false)

			consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, true)
			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumerID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, false)
		})
	}
}

func TestPSSChainLaunchAfterUpgradeTop100(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	consumerConfig := getConsumerConfig(100, nil, nil)

	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

	// we can't take validator 0 down because that's what hermes is talking to, so the jail packet wouldn't be relayed
	for i := 1; i < fresh.NUM_VALIDATORS; i++ {
		fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, i, true)
	}
}

func TestPSSChainLaunchAfterUpgradeOptIn(t *testing.T) {
	optIns := []int{0, 3, 4, 5}
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			optIn := optInFunction(t, provider, optIns...)

			consumerConfig := getConsumerConfig(fresh.PSS_OPT_IN, optInTime, optIn)
			if optInTime == optInAfterSpawn {
				// We need to opt somoene in before spawn time, or the chain will have no validators when it starts.
				consumerConfig.DuringDepositPeriod = optInFunction(t, provider, 0)
			}

			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			for i := 1; i < fresh.NUM_VALIDATORS; i++ {
				jailed := i >= 3
				fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, i, jailed)
			}

			consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
			_, err = provider.Validators[4].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumerID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, false)
		})
	}
}

func TestPSSChainLaunchWithSetCap(t *testing.T) {
	optIns := []int{0, 3, 4, 5}
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	consumerConfig := getConsumerConfig(fresh.PSS_OPT_IN, nil, nil)
	consumerConfig.ValidatorSetCap = 4
	optInDuringVoting.Set(&consumerConfig, optInFunction(t, provider, optIns...))

	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

	consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
	_, err = provider.Validators[1].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
		"provider", "opt-in", consumerID)
	require.NoError(t, err)

	hex1, err := consumer.GetValidatorHex(ctx, 1)
	require.NoError(t, err)
	require.EventuallyWithT(t, func(c *assert.CollectT) {
		power, err := fresh.GetPower(ctx, consumer, hex1)
		assert.NoError(c, err)
		assert.Greater(c, power, int64(0))
	}, 100*fresh.COMMIT_TIMEOUT, fresh.COMMIT_TIMEOUT)

	hex5, err := consumer.GetValidatorHex(ctx, 5)
	require.NoError(t, err)
	require.EventuallyWithT(t, func(c *assert.CollectT) {
		_, err := fresh.GetPower(ctx, consumer, hex5)
		assert.Error(c, err)
	}, 100*fresh.COMMIT_TIMEOUT, fresh.COMMIT_TIMEOUT)
}

func TestConsumerCommissionRate(t *testing.T) {
	optIns := []int{0}
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	wallets, err := fresh.GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerWallet := wallets[0]

	consumerConfig := getConsumerConfig(fresh.PSS_OPT_IN, nil, nil)
	consumerConfig.ShouldCopyProviderKey = fresh.AllProviderKeysCopied()
	optInDuringVoting.Set(&consumerConfig, optInFunction(t, provider, optIns...))

	consumer1 := provider.AddConsumerChain(ctx, t, consumerConfig)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer1, provider.Relayer, 1)
	consumer1Wallets, err := fresh.GetValidatorWallets(ctx, consumer1)
	require.NoError(t, err)

	for i := 1; i < fresh.NUM_VALIDATORS; i++ {
		require.NoError(t, consumer1.Validators[i].StopContainer(ctx))
	}

	consumer2 := provider.AddConsumerChain(ctx, t, consumerConfig)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer2, provider.Relayer, 1)
	consumer2Wallets, err := fresh.GetValidatorWallets(ctx, consumer2)
	require.NoError(t, err)
	for i := 1; i < fresh.NUM_VALIDATORS; i++ {
		require.NoError(t, consumer2.Validators[i].StopContainer(ctx))
	}

	consumer1Ch, err := fresh.GetTransferChannel(ctx, provider.Relayer, provider, consumer1)
	require.NoError(t, err)
	consumer2Ch, err := fresh.GetTransferChannel(ctx, provider.Relayer, provider, consumer2)
	require.NoError(t, err)
	denom1 := transfertypes.ParseDenomTrace(transfertypes.GetPrefixedDenom("transfer", consumer1Ch.ChannelID, consumer1.Config().Denom)).IBCDenom()
	denom2 := transfertypes.ParseDenomTrace(transfertypes.GetPrefixedDenom("transfer", consumer2Ch.ChannelID, consumer2.Config().Denom)).IBCDenom()
	require.NotEqual(t, denom1, denom2, "denom1: %s, denom2: %s; channel1: %s, channel2: %s", denom1, denom2, consumer1Ch.Counterparty.ChannelID, consumer2Ch.Counterparty.ChannelID)

	govAuthority, err := provider.GetGovernanceAddress(ctx)
	require.NoError(t, err)
	rewardDenomsProp := providertypes.MsgChangeRewardDenoms{
		DenomsToAdd: []string{denom1, denom2},
		Authority:   govAuthority,
	}
	prop, err := provider.BuildProposal([]cosmos.ProtoMessage{&rewardDenomsProp},
		"add denoms to list of registered reward denoms",
		"add denoms to list of registered reward denoms",
		"", fresh.GOV_DEPOSIT_AMOUNT, "", false)
	require.NoError(t, err)
	txhash, err := provider.SubmitProposal(ctx, providerWallet.Moniker, prop)
	require.NoError(t, err)
	require.NoError(t, provider.PassProposal(ctx, txhash.ProposalID))

	eg := errgroup.Group{}

	_, err = provider.Validators[0].ExecTx(ctx, providerWallet.Moniker, "distribution", "withdraw-all-rewards")
	require.NoError(t, err)

	// withdraw rewards
	_, err = provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "distribution", "withdraw-rewards", providerWallet.ValoperAddress, "--commission")
	require.NoError(t, err)

	consumerID1 := provider.GetConsumerID(ctx, t, consumer1.Config().ChainID)
	consumerID2 := provider.GetConsumerID(ctx, t, consumer2.Config().ChainID)

	eg.Go(func() error {
		_, err := provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "provider", "set-consumer-commission-rate", consumerID1, "0.5")
		return err
	})
	eg.Go(func() error {
		_, err := provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "provider", "set-consumer-commission-rate", consumerID2, "0.5")
		return err
	})
	require.NoError(t, eg.Wait())

	_, err = provider.Validators[0].ExecTx(ctx, providerWallet.Moniker, "distribution", "withdraw-rewards", providerWallet.ValoperAddress, "--commission")
	require.NoError(t, err)

	require.NoError(t, testutil.WaitForBlocks(ctx, 1, consumer1, consumer2))

	eg.Go(func() error {
		_, err := consumer1.Validators[0].ExecTx(ctx, consumer1Wallets[0].Moniker, "bank", "send", consumer1Wallets[0].Address, consumer1Wallets[1].Address, "1"+consumer1.Config().Denom, "--fees", "100000000"+consumer1.Config().Denom)
		return err
	})
	eg.Go(func() error {
		_, err := consumer2.Validators[0].ExecTx(ctx, consumer2Wallets[0].Moniker, "bank", "send", consumer2Wallets[0].Address, consumer2Wallets[1].Address, "1"+consumer2.Config().Denom, "--fees", "100000000"+consumer2.Config().Denom)
		return err
	})
	require.NoError(t, eg.Wait())

	require.NoError(t, testutil.WaitForBlocks(ctx, fresh.BLOCKS_PER_DISTRIBUTION+3, provider, consumer1, consumer2))

	rewardsDenom1 := fresh.StrToSDKInt(t, provider.QueryJSON(ctx, t, fmt.Sprintf("total.#(%%\"*%s\")", denom1), "distribution", "rewards", providerWallet.Address).String())
	rewardsDenom2 := fresh.StrToSDKInt(t, provider.QueryJSON(ctx, t, fmt.Sprintf("total.#(%%\"*%s\")", denom2), "distribution", "rewards", providerWallet.Address).String())

	require.NotEmpty(t, rewardsDenom1)
	require.NotEmpty(t, rewardsDenom2)
	require.True(t, rewardsDenom1.Sub(rewardsDenom2).Abs().LT(sdkmath.NewInt(1000)), "rewards1Int: %s, rewards2Int: %s", rewardsDenom1.String(), rewardsDenom2.String())

	_, err = provider.Validators[0].ExecTx(ctx, providerWallet.Moniker, "distribution", "withdraw-rewards", providerWallet.ValoperAddress, "--commission")
	require.NoError(t, err)

	eg.Go(func() error {
		_, err := provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "provider", "set-consumer-commission-rate", consumerID1, "0.25")
		return err
	})
	eg.Go(func() error {
		_, err := provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "provider", "set-consumer-commission-rate", consumerID2, "0.5")
		return err
	})
	require.NoError(t, eg.Wait())

	_, err = provider.GetNode().ExecTx(ctx, providerWallet.Moniker, "distribution", "withdraw-rewards", providerWallet.ValoperAddress, "--commission")
	require.NoError(t, err)

	require.NoError(t, testutil.WaitForBlocks(ctx, 1, consumer1, consumer2))

	eg.Go(func() error {
		_, err := consumer1.Validators[0].ExecTx(ctx, consumer1Wallets[0].Moniker, "bank", "send", consumer1Wallets[0].Address, consumer1Wallets[1].Address, "1"+consumer1.Config().Denom, "--fees", "100000000"+consumer1.Config().Denom)
		return err
	})
	eg.Go(func() error {
		_, err := consumer2.Validators[0].ExecTx(ctx, consumer2Wallets[0].Moniker, "bank", "send", consumer2Wallets[0].Address, consumer2Wallets[1].Address, "1"+consumer2.Config().Denom, "--fees", "100000000"+consumer2.Config().Denom)
		return err
	})
	require.NoError(t, eg.Wait())

	require.NoError(t, testutil.WaitForBlocks(ctx, fresh.BLOCKS_PER_DISTRIBUTION+3, provider, consumer1, consumer2))

	rewardsDenom1 = fresh.StrToSDKInt(t, provider.QueryJSON(ctx, t, fmt.Sprintf("total.#(%%\"*%s\")", denom1), "distribution", "rewards", providerWallet.Address).String())
	rewardsDenom2 = fresh.StrToSDKInt(t, provider.QueryJSON(ctx, t, fmt.Sprintf("total.#(%%\"*%s\")", denom2), "distribution", "rewards", providerWallet.Address).String())

	require.True(t, rewardsDenom1.GT(rewardsDenom2), "rewards1Int: %s, rewards2Int: %s", rewardsDenom1.String(), rewardsDenom2.String())
	require.False(t, rewardsDenom1.Sub(rewardsDenom2).Abs().LT(sdkmath.NewInt(1000)), "rewards1Int: %s, rewards2Int: %s", rewardsDenom1.String(), rewardsDenom2.String())
}

func TestPSSChainLaunchWithPowerCap(t *testing.T) {
	optIns := []int{1, 2, 3, 4, 5}
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	consumerConfig := getConsumerConfig(fresh.PSS_OPT_IN, nil, nil)
	cap := 50
	// This power cap is based on stake in the consumer, not the provider
	consumerConfig.ValidatorPowerCap = cap
	optInDuringVoting.Set(&consumerConfig, optInFunction(t, provider, optIns...))

	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

	// check that a small delegation works
	fresh.DelegateToValidator(ctx, t, provider, consumer, fresh.VALIDATOR_STAKE_STEP, 5, 1)

	// push validator 1 over the power cap, ensure it doesn't get reflected
	providerHex, err := provider.GetValidatorHex(ctx, 1)
	require.NoError(t, err)
	consumerHex, err := consumer.GetValidatorHex(ctx, 1)
	require.NoError(t, err)
	powerBefore, err := fresh.GetPower(ctx, consumer, consumerHex)
	require.NoError(t, err)
	wallets, err := fresh.GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	_, err = provider.Validators[1].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
		"staking", "delegate", wallets[1].ValoperAddress, fmt.Sprintf("%d%s", 30*fresh.VALIDATOR_STAKE_STEP, fresh.DENOM))
	require.NoError(t, err)
	require.EventuallyWithT(t, func(c *assert.CollectT) {
		power, err := fresh.GetPower(ctx, consumer, consumerHex)
		assert.NoError(c, err)
		assert.Greater(c, power, powerBefore)
	}, 15*time.Minute, fresh.COMMIT_TIMEOUT)
	providerPower, err := fresh.GetPower(ctx, provider, providerHex)
	require.NoError(t, err)
	consumerPower, err := fresh.GetPower(ctx, consumer, consumerHex)
	require.NoError(t, err)
	require.NotEqual(t, providerPower, consumerPower)
	require.Equal(t, int64(cap), consumerPower)
}

func TestPSSAllowlistThenModify(t *testing.T) {
	optIns := []int{0, 1, 2}
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).UpgradeVersion, true)
	// fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	wallets, err := fresh.GetValidatorWallets(ctx, provider)
	require.NoError(t, err)

	consumerConfig := getConsumerConfig(fresh.PSS_OPT_IN, nil, nil)
	consumerConfig.Allowlist = []string{
		wallets[0].ValConsAddress,
		wallets[1].ValConsAddress,
		wallets[2].ValConsAddress,
	}
	optInDuringVoting.Set(&consumerConfig, optInFunction(t, provider, optIns...))

	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

	// ensure we can't opt in a non-allowlisted validator
	consumerID := provider.GetConsumerID(ctx, t, consumer.Config().ChainID)
	_, err = provider.Validators[3].ExecTx(ctx, wallets[3].Moniker,
		"provider", "opt-in", consumerID)
	require.NoError(t, err)

	validatorCount := len(consumer.QueryJSON(ctx, t, "validators", "tendermint-validator-set").Array())
	require.Equal(t, 3, validatorCount)

	govAddress, err := provider.GetGovernanceAddress(ctx)
	msg := providertypes.MsgUpdateConsumer{
		Owner:      govAddress,
		ConsumerId: consumerID,
		PowerShapingParameters: &providertypes.PowerShapingParameters{
			Allowlist: []string{},
			Denylist:  []string{},
		},
	}
	modify, err := provider.BuildProposal([]cosmos.ProtoMessage{&msg},
		"modify consumer chain",
		"modify consumer chain",
		"", fresh.GOV_DEPOSIT_AMOUNT, "", false)
	require.NoError(t, err)
	txhash, err := provider.SubmitProposal(ctx, wallets[0].Moniker, modify)
	require.NoError(t, err)
	require.NoError(t, provider.PassProposal(ctx, txhash.ProposalID))

	// ensure we can opt in a non-allowlisted validator after the modification
	_, err = provider.Validators[3].ExecTx(ctx, wallets[3].Moniker,
		"provider", "opt-in", consumerID)
	require.NoError(t, err)

	validatorCount = len(consumer.QueryJSON(ctx, t, "validators", "tendermint-validator-set").Array())
	require.Equal(t, 4, validatorCount)
}
