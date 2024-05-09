package fresh_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

type whenToOptIn struct {
	Name string
	Set  func(*fresh.ConsumerConfig, fresh.ConsumerBootstrapCb)
}

var optInDuringDeposit = whenToOptIn{
	Name: "deposit",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.DuringDepositPeriod = bootstrapCb
	},
}

var optInDuringVoting = whenToOptIn{
	Name: "voting",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.DuringVotingPeriod = bootstrapCb
	},
}

var optInBeforeSpawn = whenToOptIn{
	Name: "before spawn",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.BeforeSpawnTime = bootstrapCb
	},
}

var optInAfterSpawn = whenToOptIn{
	Name: "after spawn",
	Set: func(config *fresh.ConsumerConfig, bootstrapCb fresh.ConsumerBootstrapCb) {
		config.AfterSpawnTime = bootstrapCb
	},
}

var optInTimes = []whenToOptIn{optInDuringDeposit, optInDuringVoting, optInBeforeSpawn, optInAfterSpawn}

func moveStake(ctx context.Context, t *testing.T, chain fresh.Chain, from, to int, amount int) {
	wallets, err := fresh.GetValidatorWallets(ctx, chain)
	require.NoError(t, err)
	_, err = chain.Validators[from].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
		"staking", "unbond", wallets[from].ValoperAddress, fmt.Sprintf("%d%s", amount, fresh.DENOM))
	require.NoError(t, err)
	_, err = chain.Validators[to].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
		"staking", "delegate", wallets[to].ValoperAddress, fmt.Sprintf("%d%s", amount, fresh.DENOM))
	require.NoError(t, err)
}

func TestPSSChainLaunchAfterUpgradeTop80(t *testing.T) {
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			const optInVal = 4

			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

			optIn := func(ctx context.Context, chain ibc.Chain) {
				pubKey, _, err := chain.(*cosmos.CosmosChain).Validators[optInVal].ExecBin(ctx, "tendermint", "show-validator")
				require.NoError(t, err)
				_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
					"provider", "opt-in", chain.Config().ChainID, string(pubKey))
				require.NoError(t, err)
			}

			consumerConfig := fresh.ConsumerConfig{
				TopN:                  80,
				ChainName:             "ics-consumer",
				Version:               "v4.0.0",
				Denom:                 fresh.CONSUMER_DENOM,
				ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
			}
			optInTime.Set(&consumerConfig, optIn)

			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			// opted in automatically
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 0, true)
			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, true)
			// did not opt in
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 5, false)

			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, false)

			// kick a validator out of the top 80
			moveStake(ctx, t, provider, 3, 2, 2*fresh.VALIDATOR_STAKE_STEP)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 3, false)

			// push a validator into the top 80
			moveStake(ctx, t, provider, 2, 4, 5*fresh.VALIDATOR_STAKE_STEP)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, true)
		})
	}
}

func TestPSSChainLaunchAfterUpgradeTop67(t *testing.T) {
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			const optInVal = 4

			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).UpgradeVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

			optIn := func(ctx context.Context, chain ibc.Chain) {
				pubKey, _, err := chain.(*cosmos.CosmosChain).Validators[optInVal].ExecBin(ctx, "tendermint", "show-validator")
				require.NoError(t, err)
				_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
					"provider", "opt-in", chain.Config().ChainID, string(pubKey))
				require.NoError(t, err)
			}

			consumerConfig := fresh.ConsumerConfig{
				TopN:                  67,
				ChainName:             "ics-consumer",
				Version:               "v4.0.0",
				Denom:                 fresh.CONSUMER_DENOM,
				ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
			}
			optInTime.Set(&consumerConfig, optIn)

			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			// opted in manually
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, true)
			// did not opt in
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 3, false)
			// opted in automatically
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 2, true)

			_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, false)
		})
	}
}

func TestPSSChainLaunchAfterUpgradeTop100(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).UpgradeVersion, true)
	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

	consumerConfig := fresh.ConsumerConfig{
		TopN:                  100,
		ChainName:             "ics-consumer",
		Version:               "v4.0.0",
		Denom:                 fresh.CONSUMER_DENOM,
		ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
	}

	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

	fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 0, true)
	fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 5, true)
}

func TestPSSChainLaunchAfterUpgradeOptIn(t *testing.T) {
	for _, optInTime := range optInTimes {
		t.Run(optInTime.Name, func(t *testing.T) {
			ctx, err := fresh.NewTestContext(t)
			require.NoError(t, err)

			provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).UpgradeVersion, true)
			fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

			require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

			optIn := func(ctx context.Context, chain ibc.Chain) {
				eg := errgroup.Group{}
				optInVals := []int{0, 2, 4}
				for _, optInVal := range optInVals {
					optInVal := optInVal
					eg.Go(func() error {
						pubKey, _, err := chain.(*cosmos.CosmosChain).Validators[optInVal].ExecBin(ctx, "tendermint", "show-validator")
						if err != nil {
							return err
						}
						_, err = provider.Validators[optInVal].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
							"provider", "opt-in", chain.Config().ChainID, string(pubKey))
						return err
					})
				}
				require.NoError(t, eg.Wait())
			}

			consumerConfig := fresh.ConsumerConfig{
				TopN:                  fresh.PSS_OPT_IN,
				ChainName:             "ics-consumer",
				Version:               "v4.0.0",
				Denom:                 fresh.CONSUMER_DENOM,
				ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
			}
			optInTime.Set(&consumerConfig, optIn)

			consumer := provider.AddConsumerChain(ctx, t, consumerConfig)

			fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 0, true)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 2, true)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 1, false)

			_, err = provider.Validators[4].ExecTx(ctx, fresh.VALIDATOR_MONIKER,
				"provider", "opt-out", consumer.Config().ChainID)
			require.NoError(t, err)
			fresh.CheckIfValidatorJailed(ctx, t, provider, consumer, 4, false)
		})
	}
}
