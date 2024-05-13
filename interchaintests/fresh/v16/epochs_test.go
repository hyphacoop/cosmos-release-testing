package v16_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestEpochsAfterV16(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		t.Skip("Test is only for v16.0.0")
	}

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
