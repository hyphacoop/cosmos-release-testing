package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestBaselineTXsAfterV16Upgrade(t *testing.T) {
	t.Parallel()
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	chain := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)

	fresh.TransactionsTest(ctx, t, chain)

	fresh.UpgradeChain(ctx, t, chain, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.TransactionsTest(ctx, t, chain)

	fresh.APIEndpointsTest(ctx, t, chain)

	fresh.RPCEndpointsTest(ctx, t, chain)
}
