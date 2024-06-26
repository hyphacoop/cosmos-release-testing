package v16_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestV16UpgradeIBCRateLimiting(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		t.Skip("Test is only for v16.0.0")
	}

	chainA, chainB, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion, fresh.DEFAULT_CHANNEL_VERSION)
	channel, err := fresh.GetTransferChannel(ctx, relayer, chainA, chainB)
	require.NoError(t, err)

	fresh.UpgradeChain(ctx, t, chainA, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.IBCTransferRateLimitedTest(ctx, t, chainA, chainB, channel)
}
