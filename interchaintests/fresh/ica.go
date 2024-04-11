package fresh

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/cosmos/gogoproto/proto"
	icatypes "github.com/cosmos/ibc-go/v7/modules/apps/27-interchain-accounts/types"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
)

func ICAControllerTest(ctx context.Context, t *testing.T, controller Chain, host Chain, relayer ibc.Relayer, isUpgraded bool) {
	wallets, err := GetValidatorWallets(ctx, controller)
	require.NoError(t, err)
	srcAddress := wallets[0].Address

	wallets, err = GetValidatorWallets(ctx, host)
	require.NoError(t, err)
	dstAddress := wallets[0].Address

	srcChannel, err := GetTransferChannel(ctx, relayer, controller, host)
	require.NoError(t, err)
	srcConnection := srcChannel.ConnectionHops[0]

	_, err = controller.Validators[0].ExecTx(ctx, srcAddress,
		"interchain-accounts", "controller", "register",
		srcConnection,
	)
	if !isUpgraded {
		require.Error(t, err)
		return
	}
	require.NoError(t, err)

	icaAddress := GetICAAddress(ctx, t, controller, srcAddress, srcConnection)
	require.NotEmpty(t, icaAddress)

	amountToSend := int64(3_300_000_000)

	_, err = controller.SendIBCTransfer(ctx, srcChannel.ChannelID, VALIDATOR_MONIKER, ibc.WalletAmount{
		Denom:   DENOM,
		Amount:  sdkmath.NewInt(amountToSend),
		Address: icaAddress,
	}, ibc.TransferOptions{})
	require.NoError(t, err)

	require.NoError(t, relayer.Flush(ctx, GetRelayerExecReporter(ctx), RelayerTransferPathFor(controller, host), srcChannel.ChannelID))

	balances, err := host.AllBalances(ctx, icaAddress)
	require.NoError(t, err)
	require.NotEmpty(t, balances)

	var ibcStakeDenom string
	for _, c := range balances {
		if strings.Contains(c.Denom, "ibc") {
			ibcStakeDenom = c.Denom
			break
		}
	}
	require.NotEmpty(t, ibcStakeDenom)

	balances, err = host.AllBalances(ctx, dstAddress)
	require.NoError(t, err)
	require.NotEmpty(t, balances)

	var recipientBalanceBefore int64
	for _, c := range balances {
		if c.Denom == ibcStakeDenom {
			recipientBalanceBefore = c.Amount.Int64()
			break
		}
	}
	icaAmount := int64(amountToSend / 3)

	sendICATx(ctx, t, controller, srcAddress, dstAddress, icaAddress, srcConnection, icaAmount, ibcStakeDenom)
	require.NoError(t, relayer.Flush(ctx, GetRelayerExecReporter(ctx), RelayerTransferPathFor(controller, host), srcChannel.ChannelID))

	balances, err = host.AllBalances(ctx, dstAddress)
	require.NoError(t, err)
	require.NotEmpty(t, balances)

	for _, c := range balances {
		if c.Denom == ibcStakeDenom {
			require.Equal(t, recipientBalanceBefore+icaAmount, c.Amount.Int64())
			break
		}
	}
}

func sendICATx(ctx context.Context, t *testing.T, controller Chain, srcAddress string, dstAddress string, icaAddress string, srcConnection string, amount int64, denom string) {
	interfaceRegistry := codectypes.NewInterfaceRegistry()
	cdc := codec.NewProtoCodec(interfaceRegistry)

	bankSendMsg := banktypes.NewMsgSend(
		sdk.MustAccAddressFromBech32(icaAddress),
		sdk.MustAccAddressFromBech32(dstAddress),
		sdk.NewCoins(sdk.NewCoin(denom, sdkmath.NewInt(amount))),
	)
	data, err := icatypes.SerializeCosmosTxWithEncoding(cdc, []proto.Message{bankSendMsg}, icatypes.EncodingProtobuf)
	require.NoError(t, err)

	msg, err := json.Marshal(icatypes.InterchainAccountPacketData{
		Type: icatypes.EXECUTE_TX,
		Data: data,
	})
	require.NoError(t, err)
	msgPath := "msg.json"
	require.NoError(t, controller.Validators[0].WriteFile(ctx, msg, msgPath))
	msgPath = controller.Validators[0].HomeDir() + "/" + msgPath
	_, err = controller.Validators[0].ExecTx(ctx, srcAddress,
		"interchain-accounts", "controller", "send-tx",
		srcConnection, msgPath,
	)
	require.NoError(t, err)
}

func GetICAAddress(ctx context.Context, t *testing.T, controller Chain, srcAddress string, srcConnection string) string {
	var icaAddress string

	// it takes a moment for it to be created
	timeoutCtx, timeoutCancel := context.WithTimeout(ctx, 90*time.Second)
	defer timeoutCancel()
	for timeoutCtx.Err() == nil {
		time.Sleep(5 * time.Second)
		stdout, _, err := controller.Validators[0].ExecQuery(timeoutCtx,
			"interchain-accounts", "controller", "interchain-account",
			srcAddress, srcConnection,
		)
		if err != nil {
			t.Logf("error querying interchain account: %s", err)
			continue
		}
		result := map[string]interface{}{}
		err = json.Unmarshal(stdout, &result)
		if err != nil {
			t.Logf("error unmarshalling interchain account: %s", err)
			continue
		}
		icaAddress = result["address"].(string)
		if icaAddress != "" {
			break
		}
	}
	return icaAddress
}
