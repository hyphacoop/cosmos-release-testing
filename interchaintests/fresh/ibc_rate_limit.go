package fresh

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	sdkmath "cosmossdk.io/math"
	abcitypes "github.com/cometbft/cometbft/abci/types"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
)

func IBCTransferRateLimitedTest(
	ctx context.Context,
	t *testing.T,
	chainA Chain,
	chainB Chain,
	channel *ibc.ChannelOutput,
) {
	addRateLimit(ctx, t, chainA, channel.ChannelID, 1)
	sendRateLimitedTx(ctx, t, chainA, chainB, channel, 1, false)

	updateRateLimit(ctx, t, chainA, channel.ChannelID, 2)
	sendRateLimitedTx(ctx, t, chainA, chainB, channel, 2, false)
	sendRateLimitedTx(ctx, t, chainA, chainB, channel, 1, true)

	outflow := chainA.QueryJSON(ctx, t, "flow.outflow", "ratelimit", "rate-limit", channel.ChannelID, "--denom", DENOM).String()
	channelValue := chainA.QueryJSON(ctx, t, "flow.channel_value", "ratelimit", "rate-limit", channel.ChannelID, "--denom", DENOM).String()
	ratio := strToSDKInt(t, outflow).Mul(sdkmath.NewInt(100)).Quo(strToSDKInt(t, channelValue)).Int64()
	require.Equal(t, int64(1), ratio)

	sendRateLimitedTx(ctx, t, chainA, chainB, channel, 1, false)
}

func sendRateLimitedTx(
	ctx context.Context,
	t *testing.T,
	chainA Chain,
	chainB Chain,
	channel *ibc.ChannelOutput,
	pctOfSupply int64,
	shouldPass bool,
) {
	wallets, err := GetValidatorWallets(ctx, chainB)
	require.NoError(t, err)
	walletB := wallets[0]

	supply, err := QuerySupply(ctx, chainA, DENOM)
	require.NoError(t, err)

	amount := supply.Amount.Mul(sdkmath.NewInt(pctOfSupply)).Quo(sdkmath.NewInt(100))

	// Use the faucet to send because it has a ton of tokens (~100T); other accounts may not have 1% of the supply
	_, err = chainA.SendIBCTransfer(ctx, channel.ChannelID, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Address: walletB.Address,
		Amount:  amount,
		Denom:   DENOM,
	}, ibc.TransferOptions{})
	if shouldPass {
		require.NoError(t, err)
	} else {
		require.Error(t, err)
	}
}

func updateRateLimit(ctx context.Context, t *testing.T, chain Chain, channelID string, pctOfSupply int64) {
	govAuthority, err := chain.GetModuleAddress(ctx, "gov")
	require.NoError(t, err)
	msg := map[string]interface{}{
		"@type":            "/ratelimit.v1.MsgUpdateRateLimit",
		"authority":        govAuthority,
		"denom":            DENOM,
		"channel_id":       channelID,
		"max_percent_send": sdkmath.NewInt(pctOfSupply).String(),
		"max_percent_recv": sdkmath.NewInt(pctOfSupply).String(),
		"duration_hours":   "48",
	}
	marshaled, err := json.Marshal(msg)
	require.NoError(t, err)
	txhash, err := chain.GetNode().SubmitProposal(ctx, VALIDATOR_MONIKER,
		cosmos.TxProposalv1{
			Title:    "Update rate limits on channel " + channelID,
			Deposit:  GOV_DEPOSIT_AMOUNT,
			Messages: []json.RawMessage{json.RawMessage(marshaled)},
			Summary:  "Update rate limits on channel " + channelID,
			Metadata: "ipfs://CID",
		})
	require.NoError(t, err)
	propID, err := GetProposalID(ctx, chain, txhash)
	require.NoError(t, err)
	require.NoError(t, chain.PassProposal(ctx, propID))
}

func addRateLimit(ctx context.Context, t *testing.T, chain Chain, channelID string, pctOfSupply int64) {
	govAuthority, err := chain.GetModuleAddress(ctx, "gov")
	require.NoError(t, err)
	msg := map[string]interface{}{
		"@type":            "/ratelimit.v1.MsgAddRateLimit",
		"authority":        govAuthority,
		"denom":            DENOM,
		"channel_id":       channelID,
		"max_percent_send": sdkmath.NewInt(pctOfSupply).String(),
		"max_percent_recv": sdkmath.NewInt(pctOfSupply).String(),
		"duration_hours":   "24",
	}
	marshaled, err := json.Marshal(msg)
	require.NoError(t, err)
	txhash, err := chain.GetNode().SubmitProposal(ctx, VALIDATOR_MONIKER,
		cosmos.TxProposalv1{
			Title:    "Add rate limits on channel " + channelID,
			Deposit:  GOV_DEPOSIT_AMOUNT,
			Messages: []json.RawMessage{json.RawMessage(marshaled)},
			Summary:  "Add rate limits on channel " + channelID,
			Metadata: "ipfs://CID",
		})
	require.NoError(t, err)
	propID, err := GetProposalID(ctx, chain, txhash)
	require.NoError(t, err)
	require.NoError(t, chain.PassProposal(ctx, propID))
}

// GetProposalID parses the proposal ID from the tx; this is necessary when the proposal type isn't in the SDK yet
func GetProposalID(ctx context.Context, chain Chain, txhash string) (string, error) {
	// we need to do this because the rate limit proposals aren't in the sdk yet,
	// so there'll be an error if we go through chain.SubmitProposal and expect it to parse the proposal ID
	stdout, _, err := chain.GetNode().ExecQuery(ctx, "tx", txhash)
	if err != nil {
		return "", err
	}
	result := struct {
		Events []abcitypes.Event `json:"events"`
	}{}
	if err := json.Unmarshal(stdout, &result); err != nil {
		return "", err
	}
	for _, event := range result.Events {
		if event.Type == "submit_proposal" {
			for _, attr := range event.Attributes {
				if string(attr.Key) == "proposal_id" {
					return string(attr.Value), nil
				}
			}
		}
	}
	return "", fmt.Errorf("proposal ID not found in tx %s", txhash)
}
