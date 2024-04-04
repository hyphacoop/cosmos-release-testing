package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestV16UpgradeIBCRateLimiting(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	chainA, chainB, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion)
	channel, err := fresh.GetTransferChannel(ctx, relayer, chainA, chainB)
	require.NoError(t, err)

	fresh.UpgradeChain(ctx, t, chainA, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.IBCTransferRateLimitedTest(ctx, t, chainA, chainB, channel)
}
