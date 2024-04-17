package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestLSMWithV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, relayer := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	stride := fresh.AddConsumerChain(ctx, t, provider, relayer, "stride", "v20.0.0", fresh.STRIDE_DENOM, []bool{false, false, false})

	lsmWallets := fresh.LSMAccountSetup(ctx, t, provider)
	strideVals, err := fresh.GetValidatorWallets(ctx, stride)
	require.NoError(t, err)

	icaAddr, err := fresh.SetupICAAccount(ctx, stride, provider, relayer, strideVals[0].Address, 1_000_000_000)
	require.NoError(t, err)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, relayer)

	fresh.LSMHappyPathTest(ctx, t, provider, stride, relayer, lsmWallets)
	fresh.ICADelegateHappyPathTest(ctx, t, provider, stride, relayer, icaAddr)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, relayer)

	fresh.LSMHappyPathTest(ctx, t, provider, stride, relayer, lsmWallets)
	fresh.ICADelegateHappyPathTest(ctx, t, provider, stride, relayer, icaAddr)
}

func TestLSMTokenizeVestedAfterV16Upgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider, _ := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)

	fresh.TokenizeVestedAmountTest(ctx, t, provider, false)

	fresh.UpgradeChain(ctx, t, provider, fresh.VALIDATOR_MONIKER, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	fresh.TokenizeVestedAmountTest(ctx, t, provider, true)
}
