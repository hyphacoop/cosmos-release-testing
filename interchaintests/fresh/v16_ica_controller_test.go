package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestV16UpgradeICAController(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	controller, host, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, false)

	fresh.UpgradeChain(ctx, t, controller, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	fresh.UpgradeChain(ctx, t, host, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.ICAControllerTest(ctx, t, controller, host, relayer, true)
}
