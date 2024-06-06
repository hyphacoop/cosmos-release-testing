package fresh

import (
	"context"
	"encoding/json"
	"fmt"
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
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/mod/semver"
)

func SetupICAAccount(ctx context.Context, controller Chain, host Chain, relayer ibc.Relayer, srcAddress string, valIdx int, initialFunds int64) (string, error) {
	srcChannel, err := GetTransferChannel(ctx, relayer, controller, host)
	if err != nil {
		return "", err
	}
	srcConnection := srcChannel.ConnectionHops[0]

	GetLogger(ctx).Sugar().Infof("VERSION IS: %s", controller.GetNode().GetBuildInformation(ctx).Version)
	if semver.Compare(semver.Major(controller.GetNode().GetBuildInformation(ctx).Version), "v17") > 0 ||
		// if we can't parse it (maybe this is a branch build), just assume it's a new version
		!semver.IsValid(controller.GetNode().GetBuildInformation(ctx).Version) {
		_, err = controller.Validators[valIdx].ExecTx(ctx, srcAddress,
			"interchain-accounts", "controller", "register",
			"--ordering", "ORDER_ORDERED",
			srcConnection,
		)
	} else {
		_, err = controller.Validators[valIdx].ExecTx(ctx, srcAddress,
			"interchain-accounts", "controller", "register",
			srcConnection,
		)
	}
	if err != nil {
		return "", err
	}

	icaAddress := GetICAAddress(ctx, controller, srcAddress, srcConnection)
	if icaAddress == "" {
		return "", fmt.Errorf("ICA address not found")
	}

	err = host.SendFunds(ctx, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Denom:   host.Config().Denom,
		Amount:  sdkmath.NewInt(initialFunds),
		Address: icaAddress,
	})
	if err != nil {
		return "", err
	}

	return icaAddress, nil
}

func ICAControllerTest(ctx context.Context, t *testing.T, controller Chain, host Chain, relayer ibc.Relayer, isUpgraded bool) {
	const amountToSend = int64(3_300_000_000)
	wallets, err := GetValidatorWallets(ctx, controller)
	require.NoError(t, err)
	valIdx := 0

	var icaAddress, srcAddress string
	for ; valIdx < len(wallets); valIdx++ {
		srcAddress = wallets[valIdx].Address
		icaAddress, err = SetupICAAccount(ctx, controller, host, relayer, srcAddress, valIdx, amountToSend)
		if !isUpgraded {
			require.Error(t, err)
			return
		} else if err == nil {
			break
		} else if strings.Contains(err.Error(), "active channel already set for this owner") {
			GetLogger(ctx).Sugar().Warnf("error setting up ICA account: %s", err)
			valIdx++
			continue
		}
		// if we get here, fail the test. Unexpected error.
		require.NoError(t, err)
	}
	if icaAddress == "" {
		// this'll happen if every validator has an ICA account already
		require.Fail(t, "unable to create ICA account")
	}

	srcChannel, err := GetTransferChannel(ctx, relayer, controller, host)
	require.NoError(t, err)

	_, err = controller.SendIBCTransfer(ctx, srcChannel.ChannelID, interchaintest.FaucetAccountKeyName, ibc.WalletAmount{
		Address: icaAddress,
		Amount:  sdkmath.NewInt(amountToSend),
		Denom:   DENOM,
	}, ibc.TransferOptions{})
	require.NoError(t, err)

	wallets, err = GetValidatorWallets(ctx, host)
	require.NoError(t, err)
	dstAddress := wallets[0].Address

	var ibcStakeDenom string
	require.EventuallyWithT(t, func(c *assert.CollectT) {
		balances, err := host.AllBalances(ctx, icaAddress)
		require.NoError(t, err)
		require.NotEmpty(t, balances)
		for _, c := range balances {
			if strings.Contains(c.Denom, "ibc") {
				ibcStakeDenom = c.Denom
				break
			}
		}
		assert.NotEmpty(c, ibcStakeDenom)
	}, 10*COMMIT_TIMEOUT, COMMIT_TIMEOUT)

	recipientBalanceBefore, err := host.GetBalance(ctx, dstAddress, ibcStakeDenom)
	require.NoError(t, err)

	icaAmount := int64(amountToSend / 3)

	srcConnection := srcChannel.ConnectionHops[0]

	sendICATx(ctx, t, controller, valIdx, srcAddress, dstAddress, icaAddress, srcConnection, icaAmount, ibcStakeDenom)

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		recipientBalanceAfter, err := host.GetBalance(ctx, dstAddress, ibcStakeDenom)
		assert.NoError(c, err)

		assert.Equal(c, recipientBalanceBefore.Add(sdkmath.NewInt(icaAmount)), recipientBalanceAfter)
	}, 10*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
}

func sendICATx(ctx context.Context, t *testing.T, controller Chain, valIdx int, srcAddress string, dstAddress string, icaAddress string, srcConnection string, amount int64, denom string) {
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
	require.NoError(t, controller.Validators[valIdx].WriteFile(ctx, msg, msgPath))
	msgPath = controller.Validators[valIdx].HomeDir() + "/" + msgPath
	_, err = controller.Validators[valIdx].ExecTx(ctx, srcAddress,
		"interchain-accounts", "controller", "send-tx",
		srcConnection, msgPath,
	)
	require.NoError(t, err)
}

func GetICAAddress(ctx context.Context, controller Chain, srcAddress string, srcConnection string) string {
	var icaAddress string

	// it takes a moment for it to be created
	timeoutCtx, timeoutCancel := context.WithTimeout(ctx, 90*time.Second)
	defer timeoutCancel()
	for timeoutCtx.Err() == nil {
		time.Sleep(5 * time.Second)
		stdout, _, err := controller.GetNode().ExecQuery(timeoutCtx,
			"interchain-accounts", "controller", "interchain-account",
			srcAddress, srcConnection,
		)
		if err != nil {
			GetLogger(ctx).Sugar().Warnf("error querying interchain account: %s", err)
			continue
		}
		result := map[string]interface{}{}
		err = json.Unmarshal(stdout, &result)
		if err != nil {
			GetLogger(ctx).Sugar().Warnf("error unmarshalling interchain account: %s", err)
			continue
		}
		icaAddress = result["address"].(string)
		if icaAddress != "" {
			break
		}
	}
	return icaAddress
}
