package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func runConsumerChainTest(t *testing.T, otherChain, otherChainVersion string, shouldCopyProviderKey [fresh.NUM_VALIDATORS]bool) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	consumerConfig := fresh.ConsumerConfig{
		ChainName:             otherChain,
		Version:               otherChainVersion,
		ShouldCopyProviderKey: shouldCopyProviderKey,
		Denom:                 fresh.CONSUMER_DENOM,
		TopN:                  fresh.PSS_DISABLED,
	}
	consumer := provider.AddConsumerChain(ctx, t, consumerConfig)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer, provider.Relayer)

	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	require.NoError(t, provider.Relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, provider.Relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer, provider.Relayer)

	consumer2 := provider.AddConsumerChain(ctx, t, consumerConfig)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer2, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer2, provider.Relayer)
	fresh.RSValidatorsJailedTest(ctx, t, provider, consumer2)
}

func TestConsumerChainLaunchesAfterV16UpgradeICS40(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v4.0.0", fresh.NoProviderKeysCopied())
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33AllKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", fresh.AllProviderKeysCopied())
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33SomeKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", fresh.SomeProviderKeysCopied())
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33NoKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", fresh.NoProviderKeysCopied())
}

func TestMainnetConsumerChainsWithV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	const neutronVersion = "v3.0.1"
	const strideVersion = "v20.0.0"

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	neutron := provider.AddConsumerChain(ctx, t, fresh.ConsumerConfig{
		ChainName:             "neutron",
		Version:               neutronVersion,
		ShouldCopyProviderKey: fresh.AllProviderKeysCopied(),
		Denom:                 fresh.NEUTRON_DENOM,
		TopN:                  fresh.PSS_DISABLED,
	})
	stride := provider.AddConsumerChain(ctx, t, fresh.ConsumerConfig{
		ChainName:             "stride",
		Version:               strideVersion,
		ShouldCopyProviderKey: fresh.AllProviderKeysCopied(),
		Denom:                 fresh.STRIDE_DENOM,
		TopN:                  fresh.PSS_DISABLED,
	})

	fresh.CCVKeyAssignmentTest(ctx, t, provider, neutron, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, neutron, provider.Relayer)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, provider.Relayer)

	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	require.NoError(t, provider.Relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, provider.Relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

	fresh.CCVKeyAssignmentTest(ctx, t, provider, neutron, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, neutron, provider.Relayer)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, provider.Relayer)
}

func TestEpochsAfterV16(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	consumer := provider.AddConsumerChain(ctx, t, fresh.ConsumerConfig{
		ChainName:             "ics-consumer",
		Version:               "v4.0.0",
		ShouldCopyProviderKey: fresh.AllProviderKeysCopied(),
		Denom:                 fresh.CONSUMER_DENOM,
		TopN:                  fresh.PSS_DISABLED,
	})

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 1)

	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	require.NoError(t, provider.Relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, provider.Relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))

	require.NoError(t, fresh.SetEpoch(ctx, provider, 20))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, provider.Relayer, 20)

	require.Error(t, fresh.SetEpoch(ctx, provider, 0))
}
