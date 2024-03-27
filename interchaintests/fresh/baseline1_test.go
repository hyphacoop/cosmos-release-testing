package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestBaseline1Upgrade(t *testing.T) {
	t.Parallel()
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	chain := fresh.CreateChains(ctx, t, fresh.GetConfig(ctx).StartVersion)

	fresh.TransactionsTest(ctx, t, chain)

	fresh.UpgradeChain(ctx, t, chain, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.TransactionsTest(ctx, t, chain)

	fresh.APIEndpointsTest(ctx, t, chain)

	fresh.RPCEndpointsTest(ctx, t, chain)
}
