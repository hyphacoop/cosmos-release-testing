package fresh

import (
	"context"
	"fmt"
	"testing"

	sdkmath "cosmossdk.io/math"
	transfertypes "github.com/cosmos/ibc-go/v7/modules/apps/transfer/types"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func AddLinkedChain(ctx context.Context, t *testing.T, chainA Chain, relayer ibc.Relayer, gaiaVersion, icsVersion string) Chain {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{createGaiaChainSpec(ctx, "gaia", gaiaVersion)},
	)

	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	chainB := Chain{chains[0].(*cosmos.CosmosChain), relayer}
	relayerWallet, err := chainB.BuildRelayerWallet(ctx, "relayer-"+chainB.Config().ChainID)
	require.NoError(t, err)

	ic := interchaintest.NewInterchain().AddChain(chainB, ibc.WalletAmount{
		Address: relayerWallet.FormattedAddress(),
		Denom:   chainB.Config().Denom,
		Amount:  sdkmath.NewInt(VALIDATOR_FUNDS),
	})

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})
	rep := GetRelayerExecReporter(ctx)
	setupRelayerKeys(ctx, t, relayer, relayerWallet, chainB)
	require.NoError(t, relayer.StopRelayer(ctx, rep))
	require.NoError(t, relayer.StartRelayer(ctx, rep))

	err = relayer.GeneratePath(ctx, rep, chainA.Config().ChainID, chainB.Config().ChainID, RelayerTransferPathFor(chainA, chainB))
	require.NoError(t, err)

	err = relayer.LinkPath(ctx, rep, RelayerTransferPathFor(chainA, chainB), ibc.CreateChannelOptions{
		DestPortName:   TRANSFER_PORT_ID,
		SourcePortName: TRANSFER_PORT_ID,
		Order:          ibc.Unordered,
		Version:        icsVersion,
	}, ibc.DefaultClientOpts())
	require.NoError(t, err)

	return chainB
}

func setupRelayerKeys(ctx context.Context, t *testing.T, relayer ibc.Relayer, wallet ibc.Wallet, chain Chain) {
	rep := GetRelayerExecReporter(ctx)
	rpcAddr, grpcAddr := chain.GetRPCAddress(), chain.GetGRPCAddress()
	if !relayer.UseDockerNetwork() {
		rpcAddr, grpcAddr = chain.GetHostRPCAddress(), chain.GetHostGRPCAddress()
	}

	chainName := chain.Config().ChainID
	require.NoError(t, relayer.AddChainConfiguration(ctx,
		rep,
		chain.Config(), chainName,
		rpcAddr, grpcAddr,
	))

	require.NoError(t, relayer.RestoreKey(ctx,
		rep,
		chain.Config(), chainName,
		wallet.Mnemonic(),
	))
}

func IBCTxWithFeeTest(ctx context.Context, t *testing.T, chainA, chainB Chain, relayer ibc.Relayer, hasFeeModule bool) {

	const (
		recvFee    = 1_000
		ackFee     = 2_000
		timeoutFee = 3_000
		sendAmount = int64(1_000_000)
	)

	wallets, err := GetValidatorWallets(ctx, chainA)
	require.NoError(t, err)
	srcWallet := wallets[0]

	wallets, err = GetValidatorWallets(ctx, chainB)
	require.NoError(t, err)
	dstWallet := wallets[0]

	channel, err := GetTransferChannel(ctx, relayer, chainA, chainB)
	require.NoError(t, err)

	relayerWallet, ok := relayer.GetWallet(chainA.Config().ChainID)
	require.True(t, ok)
	relayerBalanceBefore, err := chainA.GetBalance(ctx, string(relayerWallet.Address()), DENOM)
	require.NoError(t, err)

	require.NoError(t, relayer.StopRelayer(ctx, GetRelayerExecReporter(ctx)))

	_, err = chainA.SendIBCTransfer(ctx, channel.ChannelID, srcWallet.Address, ibc.WalletAmount{
		Address: dstWallet.Address,
		Amount:  sdkmath.NewInt(sendAmount),
		Denom:   DENOM,
	}, ibc.TransferOptions{})
	require.NoError(t, err)

	balanceBefore, err := chainA.GetBalance(ctx, srcWallet.Address, DENOM)
	require.NoError(t, err)

	_, err = chainA.GetNode().ExecTx(ctx, srcWallet.Address,
		"ibc-fee", "pay-packet-fee", TRANSFER_PORT_ID, channel.ChannelID, "1",
		"--recv-fee", fmt.Sprintf("%d%s", recvFee, DENOM),
		"--ack-fee", fmt.Sprintf("%d%s", ackFee, DENOM),
		"--timeout-fee", fmt.Sprintf("%d%s", timeoutFee, DENOM),
	)
	if hasFeeModule {
		require.NoError(t, err)
		balanceAfter, err := chainA.GetBalance(ctx, srcWallet.Address, DENOM)
		require.NoError(t, err)
		require.LessOrEqual(t, balanceAfter.Int64(), balanceBefore.Int64()-recvFee-ackFee-timeoutFee)
	} else {
		require.Error(t, err)
	}

	require.NoError(t, relayer.StartRelayer(ctx, GetRelayerExecReporter(ctx)))

	expectedDenom := transfertypes.ParseDenomTrace(transfertypes.GetPrefixedDenom(TRANSFER_PORT_ID, channel.Counterparty.ChannelID, DENOM)).IBCDenom()
	require.EventuallyWithT(t, func(c *assert.CollectT) {
		balance, err := chainB.GetBalance(ctx, dstWallet.Address, expectedDenom)
		assert.NoError(c, err)
		balances, err := chainB.AllBalances(ctx, dstWallet.Address)
		assert.NoError(c, err)
		assert.Equalf(c, sendAmount, balance.Int64(), "expected balance %d%s, got %d, all balances: %v", sendAmount, expectedDenom, balance.Int64(), balances)
	}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

	if hasFeeModule {
		require.EventuallyWithT(t, func(c *assert.CollectT) {
			relayerBalanceAfter, err := chainA.GetBalance(ctx, string(relayerWallet.Address()), DENOM)
			assert.NoError(c, err)
			assert.Greater(c, relayerBalanceAfter.Int64(), relayerBalanceBefore.Int64())
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
	} else {
		require.Never(t, func() bool {
			relayerBalanceAfter, err := chainA.GetBalance(ctx, string(relayerWallet.Address()), DENOM)
			require.NoError(t, err)
			return relayerBalanceAfter.Int64() > relayerBalanceBefore.Int64()
		}, 15*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
	}
}
