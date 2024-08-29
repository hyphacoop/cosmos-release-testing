package v16_test

import (
	"testing"

	ibcfeetypes "github.com/cosmos/ibc-go/v8/modules/apps/29-fee/types"
	transfertypes "github.com/cosmos/ibc-go/v8/modules/apps/transfer/types"
	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/stretchr/testify/require"
)

func TestIBCFeeMiddlewareAfterV16(t *testing.T) {
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)
	if fresh.GetConfig(ctx).TargetVersion != "v16" {
		t.Skip("Test is only for v16.0.0")
	}

	feeTransferVersion := string(ibcfeetypes.ModuleCdc.MustMarshalJSON(&ibcfeetypes.Metadata{FeeVersion: ibcfeetypes.Version, AppVersion: transfertypes.Version}))
	chainA, chainB, relayer := fresh.CreateLinkedChains(ctx, t, fresh.GetConfig(ctx).StartVersion, fresh.DEFAULT_CHANNEL_VERSION)
	fresh.IBCTxWithFeeTest(ctx, t, chainA, chainB, relayer, false)

	fresh.UpgradeChain(ctx, t, chainA, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)
	fresh.IBCTxWithFeeTest(ctx, t, chainA, chainB, relayer, false)

	// We can't launch a chain on the old version with the fee module enabled, so that case isn't tested.
	chainC := fresh.AddLinkedChain(ctx, t, chainA, relayer, fresh.GetConfig(ctx).UpgradeVersion, feeTransferVersion)
	fresh.IBCTxWithFeeTest(ctx, t, chainA, chainC, relayer, true)

	chainD := fresh.AddLinkedChain(ctx, t, chainA, relayer, fresh.GetConfig(ctx).UpgradeVersion, fresh.DEFAULT_CHANNEL_VERSION)
	fresh.IBCTxWithFeeTest(ctx, t, chainA, chainD, relayer, false)
}
