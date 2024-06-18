package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestICAController(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	alreadyUpgraded := false
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		alreadyUpgraded = true
	}

	controller, host, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion, fresh.DEFAULT_CHANNEL_VERSION)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, alreadyUpgraded)

	fresh.UpgradeChain(ctx, t, controller, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, true)
}
