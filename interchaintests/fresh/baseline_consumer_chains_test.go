package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func runConsumerChainTest(t *testing.T, otherChain, otherChainVersion string, shouldCopyProviderKey []bool) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, relayer := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	consumer := fresh.AddConsumerChain(ctx, t, provider, relayer, otherChain, otherChainVersion, fresh.CONSUMER_DENOM, shouldCopyProviderKey)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer, relayer)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	require.NoError(t, relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer, relayer)

	consumer2 := fresh.AddConsumerChain(ctx, t, provider, relayer, otherChain, otherChainVersion, fresh.CONSUMER_DENOM, shouldCopyProviderKey)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer2, relayer, 1)
	fresh.IBCTest(ctx, t, provider, consumer2, relayer)
	fresh.ValidatorJailedTest(ctx, t, provider, consumer2, relayer)
}

func TestConsumerChainLaunchesAfterV16UpgradeICS40(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v4.0.0", []bool{true, true, true})
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33AllKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", []bool{true, true, true})
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33SomeKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", []bool{false, true, true})
}

func TestConsumerChainLaunchesAfterV16UpgradeICS33NoKeysCopied(t *testing.T) {
	runConsumerChainTest(t, "ics-consumer", "v3.3.0", []bool{false, false, false})
}

func TestMainnetConsumerChainsWithV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	const neutronVersion = "v3.0.1"
	const strideVersion = "v20.0.0"

	provider, relayer := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	neutron := fresh.AddConsumerChain(ctx, t, provider, relayer, "neutron", neutronVersion, fresh.NEUTRON_DENOM, []bool{true, true, true})
	stride := fresh.AddConsumerChain(ctx, t, provider, relayer, "stride", strideVersion, fresh.STRIDE_DENOM, []bool{true, true, true})

	fresh.CCVKeyAssignmentTest(ctx, t, provider, neutron, relayer, 1)
	fresh.IBCTest(ctx, t, provider, neutron, relayer)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, relayer)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	require.NoError(t, relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))

	fresh.CCVKeyAssignmentTest(ctx, t, provider, neutron, relayer, 1)
	fresh.IBCTest(ctx, t, provider, neutron, relayer)
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, relayer)
}

func TestEpochsAfterV16(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, relayer := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	consumer := fresh.AddConsumerChain(ctx, t, provider, relayer, "ics-consumer", "v4.0.0", fresh.CONSUMER_DENOM, []bool{true, true, true})

	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, relayer, 1)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	require.NoError(t, relayer.StopRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))
	require.NoError(t, relayer.StartRelayer(ctx, fresh.GetRelayerExecReporter(ctx)))

	require.NoError(t, fresh.SetEpoch(ctx, provider, 20))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, consumer, relayer, 20)

	require.Error(t, fresh.SetEpoch(ctx, provider, 0))
}
