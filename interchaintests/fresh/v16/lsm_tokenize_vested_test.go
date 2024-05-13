package v16_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestLSMTokenizeVestedAfterV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		t.Skip("Test is only for v16.0.0")
	}

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)

	fresh.TokenizeVestedAmountTest(ctx, t, provider, false)

	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.TokenizeVestedAmountTest(ctx, t, provider, true)
}
