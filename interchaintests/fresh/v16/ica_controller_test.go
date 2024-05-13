package v16_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestV16UpgradeICAController(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		t.Skip("Test is only for v16.0.0")
	}

	controller, host, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion, fresh.DEFAULT_CHANNEL_VERSION)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, false)

	fresh.UpgradeChain(ctx, t, controller, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, true)
}
