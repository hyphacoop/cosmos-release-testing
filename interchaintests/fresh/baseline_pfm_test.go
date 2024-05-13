package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestPFMAfterUpgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	chains, relayer := fresh.CreateNLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion, fresh.DEFAULT_CHANNEL_VERSION, 4)
	fresh.PFMTransfersTest(ctx, t, chains, relayer)

	fresh.UpgradeChain(ctx, t, chains[0], fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	fresh.PFMTransfersTest(ctx, t, chains, relayer)
}
