package fresh_test

import (
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestLSMAfterUpgrade(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	provider := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, true)
	stride := provider.AddConsumerChain(ctx, t, fresh.ConsumerConfig{
		ChainName:             "stride",
		Version:               "v20.0.0",
		Denom:                 fresh.STRIDE_DENOM,
		ShouldCopyProviderKey: fresh.NoProviderKeysCopied(),
		TopN:                  fresh.PSS_DISABLED,
	})

	lsmWallets := fresh.LSMAccountSetup(ctx, t, provider)
	strideVals, err := fresh.GetValidatorWallets(ctx, stride)
	require.NoError(t, err)

	icaAddr, err := fresh.SetupICAAccount(ctx, stride, provider, provider.Relayer, strideVals[0].Address, 0, 1_000_000_000)
	require.NoError(t, err)

	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, provider.Relayer)

	fresh.LSMHappyPathTest(ctx, t, provider, stride, provider.Relayer, lsmWallets)
	fresh.ICADelegateHappyPathTest(ctx, t, provider, stride, provider.Relayer, icaAddr)

	fresh.UpgradeChain(ctx, t, provider, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	require.NoError(t, fresh.SetEpoch(ctx, provider, 1))
	fresh.CCVKeyAssignmentTest(ctx, t, provider, stride, provider.Relayer, 1)
	fresh.IBCTest(ctx, t, provider, stride, provider.Relayer)

	fresh.LSMHappyPathTest(ctx, t, provider, stride, provider.Relayer, lsmWallets)
	fresh.ICADelegateHappyPathTest(ctx, t, provider, stride, provider.Relayer, icaAddr)
}
