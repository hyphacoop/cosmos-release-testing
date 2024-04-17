package fresh

import (
	"context"
	"encoding/json"
	"testing"

	transfertypes "github.com/cosmos/ibc-go/v7/modules/apps/transfer/types"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func PFMTransfersTest(ctx context.Context, t *testing.T, chains []Chain, relayer ibc.Relayer) {
	// forwardChannels[0] = chain0 -> chain1, forwardChannels[1] = chain1 -> chain2, forwardChannels[2] = chain2 -> chain3
	var forwardChannels []*ibc.ChannelOutput
	targetDenomAD := chains[0].Config().Denom
	for i := 0; i < len(chains)-1; i++ {
		transferCh, err := GetTransferChannel(ctx, relayer, chains[i], chains[i+1])
		require.NoError(t, err)
		forwardChannels = append(forwardChannels, transferCh)
		targetDenomAD = transfertypes.GetPrefixedDenom(transferCh.PortID, transferCh.ChannelID, targetDenomAD)
	}
	targetDenomAD = transfertypes.ParseDenomTrace(targetDenomAD).IBCDenom()

	// backwardChannels[2] = chain3 -> chain2, backwardChannels[1] = chain2 -> chain1, backwardChannels[0] = chain1 -> chain0
	backwardChannels := make([]*ibc.ChannelOutput, len(forwardChannels))
	targetDenomDA := chains[3].Config().Denom
	for i := len(chains) - 1; i > 0; i-- {
		transferCh, err := GetTransferChannel(ctx, relayer, chains[i], chains[i-1])
		require.NoError(t, err)
		backwardChannels[i-1] = transferCh
		targetDenomDA = transfertypes.GetPrefixedDenom(transferCh.PortID, transferCh.ChannelID, targetDenomDA)
	}
	targetDenomDA = transfertypes.ParseDenomTrace(targetDenomDA).IBCDenom()

	dWallets, err := GetValidatorWallets(ctx, chains[3])
	require.NoError(t, err)
	dWallet1 := dWallets[0]

	aWallets, err := GetValidatorWallets(ctx, chains[0])
	require.NoError(t, err)
	aWallet1 := aWallets[0]

	dStartBalance, err := chains[3].GetBalance(ctx, dWallet1.Address, targetDenomAD)
	require.NoError(t, err)

	timeout := "10m"
	memo := map[string]interface{}{
		"forward": map[string]interface{}{
			"receiver": "pfm",
			"port":     "transfer",
			"channel":  forwardChannels[1].ChannelID,
			"timeout":  timeout,
			"next": map[string]interface{}{
				"forward": map[string]interface{}{
					"receiver": dWallet1.Address,
					"port":     "transfer",
					"channel":  forwardChannels[2].ChannelID,
					"timeout":  timeout,
				},
			},
		},
	}
	memoBytes, err := json.Marshal(memo)
	require.NoError(t, err)
	_, err = chains[0].GetNode().ExecTx(ctx, aWallet1.Address,
		"ibc-transfer", "transfer", "transfer", forwardChannels[0].ChannelID, "pfm", "1000000"+DENOM,
		"--memo", string(memoBytes))
	require.NoError(t, err)

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		dEndBalance, err := chains[3].GetBalance(ctx, dWallet1.Address, targetDenomAD)
		assert.NoError(c, err)
		balances, err := chains[3].AllBalances(ctx, dWallet1.Address)
		assert.NoError(c, err)
		assert.Truef(c, dEndBalance.GT(dStartBalance), "expected %d > %d in %s; balances are: %+v",
			dEndBalance, dStartBalance, targetDenomAD, balances)
	}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT, "chain D balance has not increased")

	aStartBalance, err := chains[0].GetBalance(ctx, aWallet1.Address, targetDenomDA)
	require.NoError(t, err)

	memo = map[string]interface{}{
		"forward": map[string]interface{}{
			"receiver": "pfm",
			"port":     "transfer",
			"channel":  backwardChannels[1].ChannelID,
			"timeout":  timeout,
			"next": map[string]interface{}{
				"forward": map[string]interface{}{
					"receiver": aWallet1.Address,
					"port":     "transfer",
					"channel":  backwardChannels[0].ChannelID,
					"timeout":  timeout,
				},
			},
		},
	}
	memoBytes, err = json.Marshal(memo)
	require.NoError(t, err)
	_, err = chains[3].GetNode().ExecTx(ctx, dWallet1.Address,
		"ibc-transfer", "transfer", "transfer", backwardChannels[2].ChannelID, "pfm", "1000000"+chains[3].Config().Denom,
		"--memo", string(memoBytes))
	require.NoError(t, err)

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		aEndBalance, err := chains[0].GetBalance(ctx, aWallet1.Address, targetDenomDA)
		assert.NoError(c, err)
		balances, err := chains[0].AllBalances(ctx, aWallet1.Address)
		assert.NoError(c, err)
		assert.Truef(c, aEndBalance.GT(aStartBalance), "expected %d > %d in %s; balances are: %+v",
			aEndBalance, aStartBalance, targetDenomDA, balances)
	}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT, "chain A balance has not increased")
}
