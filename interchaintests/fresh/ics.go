package fresh

import (
	"context"
	"fmt"
	"strconv"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/types"
	clienttypes "github.com/cosmos/ibc-go/v7/modules/core/02-client/types"
	ccvclient "github.com/cosmos/interchain-security/v3/x/ccv/provider/client"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
)

func isValoperJailed(ctx context.Context, t *testing.T, provider *cosmos.CosmosChain, valoper string) bool {
	out, _, err := provider.Validators[0].ExecQuery(ctx, "staking", "validator", valoper)
	require.NoError(t, err)
	return gjson.GetBytes(out, "jailed").Bool()
}

func ValidatorJailedTest(ctx context.Context, t *testing.T, provider *cosmos.CosmosChain, consumer *cosmos.CosmosChain, relayer ibc.Relayer) {
	require.NoError(t, consumer.Validators[1].StopContainer(ctx))
	require.NoError(t, consumer.Validators[2].StopContainer(ctx))

	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	valoper2 := wallets[1].ValoperAddress
	valoper3 := wallets[2].ValoperAddress

	require.Eventually(t, func() bool {
		return isValoperJailed(ctx, t, provider, valoper2)
	}, 30*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
	require.False(t, isValoperJailed(ctx, t, provider, valoper3))

	require.NoError(t, consumer.Validators[1].StartContainer(ctx))
	provider.Validators[1].ExecTx(ctx, wallets[1].Moniker, "slashing", "unjail")
	require.False(t, isValoperJailed(ctx, t, provider, valoper2))
}

func CCVKeyAssignmentTest(ctx context.Context, t *testing.T, provider, consumer *cosmos.CosmosChain, relayer ibc.Relayer) {
	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerAddress := wallets[0]

	json, err := provider.Validators[0].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	providerHex := gjson.GetBytes(json, "address").String()
	json, err = consumer.Validators[0].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	consumerHex := gjson.GetBytes(json, "address").String()

	var providerPowerBefore int64
	CheckEndpoint(ctx, t, provider.GetHostRPCAddress()+"/validators", func(b []byte) error {
		providerPowerBefore = gjson.GetBytes(b, fmt.Sprintf("result.validators.#(address==\"%s\").voting_power", providerHex)).Int()
		if providerPowerBefore == 0 {
			return fmt.Errorf("provider validator %s power not found; validators are: %s", providerHex, string(b))
		}
		return nil
	})

	_, err = provider.Validators[0].ExecTx(ctx, providerAddress.Moniker,
		"staking", "delegate",
		providerAddress.ValoperAddress, fmt.Sprintf("%d%s", VALIDATOR_STAKE_STEP, DENOM),
	)
	require.NoError(t, err)

	require.Eventually(t, func() bool {
		var providerPower int64
		CheckEndpoint(ctx, t, provider.GetHostRPCAddress()+"/validators", func(b []byte) error {
			providerPower = gjson.GetBytes(b, fmt.Sprintf("result.validators.#(address==\"%s\").voting_power", providerHex)).Int()
			if providerPower == 0 {
				return fmt.Errorf("provider validator %s power not found; validators are: %s", providerHex, string(b))
			}
			return nil
		})

		var consumerPower int64
		CheckEndpoint(ctx, t, consumer.GetHostRPCAddress()+"/validators", func(b []byte) error {
			consumerPower = gjson.GetBytes(b, fmt.Sprintf("result.validators.#(address==\"%s\").voting_power", consumerHex)).Int()
			if consumerPower == 0 {
				return fmt.Errorf("consumer validator %s power not found; validators are: %s", consumerHex, string(b))
			}
			return nil
		})
		if providerPowerBefore >= providerPower {
			return false
		}
		return providerPower == consumerPower
	}, 10*time.Minute, COMMIT_TIMEOUT)
}

func AddConsumerChain(ctx context.Context, t *testing.T, provider *cosmos.CosmosChain, relayer ibc.Relayer, chainName, version, denom string, shouldCopyProviderKey []bool) *cosmos.CosmosChain {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	if len(shouldCopyProviderKey) != NUM_VALIDATORS {
		panic(fmt.Sprintf("shouldCopyProviderKey must be the same length as the number of validators (%d)", NUM_VALIDATORS))
	}

	chainID := fmt.Sprintf("%s-%d", chainName, len(provider.Consumers)+1)
	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{createConsumerChainSpec(ctx, chainID, chainName, denom, version, shouldCopyProviderKey)},
	)
	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	consumer := chains[0].(*cosmos.CosmosChain)

	// We can't use AddProviderConsumerLink here because the provider chain is already built; we'll have to do everything by hand.
	provider.Consumers = append(provider.Consumers, consumer)
	consumer.Provider = provider

	consumerAdditionProposal(ctx, t, chainID, provider)

	wallet, err := consumer.BuildRelayerWallet(ctx, "relayer-"+consumer.Config().ChainID)
	require.NoError(t, err)
	ic := interchaintest.NewInterchain().
		AddChain(consumer, ibc.WalletAmount{
			Address: wallet.FormattedAddress(),
			Denom:   consumer.Config().Denom,
			Amount:  sdkmath.NewInt(VALIDATOR_FUNDS),
		}).
		AddRelayer(relayer, "relayer")

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})

	setupRelayerKeys(ctx, t, relayer, wallet, consumer)
	connectChains(ctx, t, provider, consumer, relayer)

	return consumer
}

func createConsumerChainSpec(ctx context.Context, chainID, chainType, denom, version string, shouldCopyProviderKey []bool) *interchaintest.ChainSpec {
	fullNodes := 0
	validators := 3

	bechPrefix := ""
	if chainType == "ics-consumer" {
		majorVersion, err := strconv.Atoi(version[1:2])
		if err != nil {
			// this really shouldn't happen unless someone misconfigured something
			panic(fmt.Sprintf("failed to parse major version from %s: %v", version, err))
		}
		if majorVersion >= 4 {
			bechPrefix = "consumer"
		}
	} else if chainType == "stride" {
		bechPrefix = "stride"
	}
	genesisOverrides := []cosmos.GenesisKV{
		cosmos.NewGenesisKV("app_state.slashing.params.signed_blocks_window", strconv.Itoa(SLASHING_WINDOW_CONSUMER)),
		cosmos.NewGenesisKV("consensus_params.block.max_gas", "50000000"),
	}
	if chainType == "neutron" {
		genesisOverrides = append(genesisOverrides,
			cosmos.NewGenesisKV("app_state.globalfee.params.minimum_gas_prices", []interface{}{
				map[string]interface{}{
					"amount": "0.005",
					"denom":  denom,
				},
			}),
		)
	}

	return &interchaintest.ChainSpec{
		Name:          chainType,
		Version:       version,
		ChainName:     chainID,
		NumFullNodes:  &fullNodes,
		NumValidators: &validators,
		ChainConfig: ibc.ChainConfig{
			Denom:         denom,
			GasPrices:     "0.005" + denom,
			ChainID:       chainID,
			GasAdjustment: 2.0,
			ConfigFileOverrides: map[string]any{
				"config/config.toml": createConfigToml(),
			},
			Bech32Prefix: bechPrefix,
			ModifyGenesisAmounts: func(i int) (types.Coin, types.Coin) {
				return types.Coin{
						Amount: sdkmath.NewInt(VALIDATOR_FUNDS),
						Denom:  denom,
					}, types.Coin{
						Amount: sdkmath.NewInt(getValidatorStake()[i]),
						Denom:  denom,
					}
			},
			ModifyGenesis: cosmos.ModifyGenesis(genesisOverrides),
			ConsumerCopyProviderKey: func(i int) bool {
				return shouldCopyProviderKey[i]
			},
		},
	}
}

func setupRelayerKeys(ctx context.Context, t *testing.T, relayer ibc.Relayer, wallet ibc.Wallet, chain *cosmos.CosmosChain) error {
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

	return nil
}

func connectChains(ctx context.Context, t *testing.T, provider *cosmos.CosmosChain, consumer *cosmos.CosmosChain, relayer ibc.Relayer) {
	icsPath := RelayerICSPathFor(provider, consumer)
	rep := GetRelayerExecReporter(ctx)
	require.NoError(t, relayer.GeneratePath(ctx, rep, consumer.Config().ChainID, provider.Config().ChainID, icsPath))

	consumerClients, err := relayer.GetClients(ctx, rep, consumer.Config().ChainID)
	require.NoError(t, err)

	var consumerClient *ibc.ClientOutput
	for _, client := range consumerClients {
		if client.ClientState.ChainID == provider.Config().ChainID {
			consumerClient = client
			break
		}
	}
	require.NotNilf(t, consumerClient, "consumer chain %s does not have a client tracking the provider chain %s", consumer.Config().ChainID, provider.Config().ChainID)
	consumerClientID := consumerClient.ClientID

	providerClients, err := relayer.GetClients(ctx, rep, provider.Config().ChainID)
	require.NoError(t, err)

	var providerClient *ibc.ClientOutput
	for _, client := range providerClients {
		if client.ClientState.ChainID == consumer.Config().ChainID {
			providerClient = client
			break
		}
	}
	require.NotNilf(t, providerClient, "provider chain %s does not have a client tracking the consumer chain %s for path %s on relayer %s",
		provider.Config().ChainID, consumer.Config().ChainID, icsPath, relayer)
	providerClientID := providerClient.ClientID

	require.NoError(t, relayer.UpdatePath(ctx, rep, icsPath, ibc.PathUpdateOptions{
		SrcClientID: &consumerClientID,
		DstClientID: &providerClientID,
	}))

	require.NoError(t, relayer.CreateConnections(ctx, rep, icsPath))

	require.NoError(t, relayer.CreateChannel(ctx, rep, icsPath, ibc.CreateChannelOptions{
		SourcePortName: "consumer",
		DestPortName:   "provider",
		Order:          ibc.Ordered,
		Version:        "1",
	}))

	require.NoError(t, relayer.StopRelayer(ctx, rep))
	require.NoError(t, relayer.StartRelayer(ctx, rep))
	require.Eventually(t, func() bool {
		providerTxChannel, err := GetTransferChannel(ctx, relayer, provider, consumer)
		return err == nil && providerTxChannel != nil
	}, 2*time.Minute, 10*time.Second)
}

func consumerAdditionProposal(ctx context.Context, t *testing.T, chainID string, provider *cosmos.CosmosChain) {
	prop := ccvclient.ConsumerAdditionProposalJSON{
		Title:         fmt.Sprintf("Addition of %s consumer chain", chainID),
		Summary:       "Proposal to add new consumer chain",
		ChainId:       chainID,
		InitialHeight: clienttypes.Height{RevisionNumber: clienttypes.ParseChainID(chainID), RevisionHeight: 1},
		GenesisHash:   []byte("gen_hash"),
		BinaryHash:    []byte("bin_hash"),
		SpawnTime:     time.Now(),

		BlocksPerDistributionTransmission: 1000,
		CcvTimeoutPeriod:                  2419200000000000,
		TransferTimeoutPeriod:             3600000000000,
		ConsumerRedistributionFraction:    "0.75",
		HistoricalEntries:                 10000,
		UnbondingPeriod:                   1728000000000000,
		Deposit:                           GOV_DEPOSIT_AMOUNT,
	}
	propTx, err := provider.ConsumerAdditionProposal(ctx, VALIDATOR_MONIKER, prop)
	require.NoError(t, err)
	PassProposal(ctx, t, provider, propTx.ProposalID)
}
