package fresh_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
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

func optInFunction(t *testing.T, producer fresh.Chain, validators ...int) func(context.Context, *cosmos.CosmosChain) {
	return func(ctx context.Context, consumer *cosmos.CosmosChain) {
		eg := errgroup.Group{}
		for _, i := range validators {
			i := i
			eg.Go(func() error {
				_, err := producer.Validators[i].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
					"provider", "opt-in", consumer.Config().ChainID)
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
		Version:               "v4.0.0",
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

			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, true)
			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, false)

			_, err = provider.Validators[3].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
			require.Error(t, err)

			// kick a validator out of the top 80, and push a different one in
			wallets, err := fresh.GetValidatorWallets(ctx, provider)
			require.NoError(t, err)
			_, err = provider.Validators[5].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"staking", "delegate", wallets[5].ValoperAddress, fmt.Sprintf("%d%s", 20*fresh.VALIDATOR_STAKE_STEP, fresh.DENOM))
			require.NoError(t, err)
			require.NoError(t, testutil.WaitForBlocks(ctx, 10, consumer))

			_, err = provider.Validators[3].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
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

			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, optInVal, true)
			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
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

			_, err = provider.Validators[4].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
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

	pubKey, _, err := consumer.Validators[1].ExecBin(ctx, "tendermint", "show-validator")
	require.NoError(t, err)
	_, err = provider.Validators[1].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
		"provider", "opt-in", consumer.Config().ChainID, string(pubKey))
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
