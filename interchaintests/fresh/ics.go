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
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
	"github.com/tidwall/sjson"
)

func isValoperJailed(ctx context.Context, t *testing.T, provider Chain, valoper string) bool {
	out, _, err := provider.Validators[0].ExecQuery(ctx, "staking", "validator", valoper)
	require.NoError(t, err)
	return gjson.GetBytes(out, "jailed").Bool()
}

func ValidatorJailedTest(ctx context.Context, t *testing.T, provider Chain, consumer Chain, relayer ibc.Relayer) {
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
	time.Sleep(10 * COMMIT_TIMEOUT)
	_, err = provider.Validators[1].ExecTx(ctx, wallets[1].Moniker, "slashing", "unjail")
	require.NoError(t, err)
	require.False(t, isValoperJailed(ctx, t, provider, valoper2))
}

func getPower(ctx context.Context, t *testing.T, chain Chain, hexaddr string) int64 {
	var power int64
	CheckEndpoint(ctx, t, chain.GetHostRPCAddress()+"/validators", func(b []byte) error {
		power = gjson.GetBytes(b, fmt.Sprintf("result.validators.#(address==\"%s\").voting_power", hexaddr)).Int()
		if power == 0 {
			return fmt.Errorf("validator %s power not found; validators are: %s", hexaddr, string(b))
		}
		return nil
	})
	return power
}

func CCVKeyAssignmentTest(ctx context.Context, t *testing.T, provider, consumer Chain, relayer ibc.Relayer, blocksPerEpoch int) {
	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerAddress := wallets[0]

	json, err := provider.Validators[0].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	providerHex := gjson.GetBytes(json, "address").String()
	json, err = consumer.Validators[0].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	consumerHex := gjson.GetBytes(json, "address").String()

	providerPowerBefore := getPower(ctx, t, provider, providerHex)

	_, err = provider.Validators[0].ExecTx(ctx, providerAddress.Moniker,
		"staking", "delegate",
		providerAddress.ValoperAddress, fmt.Sprintf("%d%s", VALIDATOR_STAKE_STEP, DENOM),
	)
	require.NoError(t, err)

	if blocksPerEpoch > 1 {
		require.Greater(t, getPower(ctx, t, provider, providerHex), providerPowerBefore)
		require.NotEqual(t, getPower(ctx, t, provider, providerHex), getPower(ctx, t, consumer, consumerHex))
		require.NoError(t, testutil.WaitForBlocks(ctx, blocksPerEpoch, provider))
	}

	require.Eventually(t, func() bool {
		providerPower := getPower(ctx, t, provider, providerHex)
		consumerPower := getPower(ctx, t, consumer, consumerHex)
		if providerPowerBefore >= providerPower {
			return false
		}
		return providerPower == consumerPower
	}, 10*time.Minute, COMMIT_TIMEOUT)
}

func AddConsumerChain(ctx context.Context, t *testing.T, provider Chain, relayer ibc.Relayer, chainName, version, denom string, shouldCopyProviderKey []bool) Chain {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	if len(shouldCopyProviderKey) != NUM_VALIDATORS {
		panic(fmt.Sprintf("shouldCopyProviderKey must be the same length as the number of validators (%d)", NUM_VALIDATORS))
	}

	chainID := fmt.Sprintf("%s-%d", chainName, len(provider.Consumers)+1)
	spawnTime := consumerAdditionProposal(ctx, t, chainID, provider)

	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{createConsumerChainSpec(ctx, provider, chainID, chainName, denom, version, shouldCopyProviderKey, spawnTime)},
	)
	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	consumer := Chain{chains[0].(*cosmos.CosmosChain)}

	// We can't use AddProviderConsumerLink here because the provider chain is already built; we'll have to do everything by hand.
	provider.Consumers = append(provider.Consumers, consumer.CosmosChain)
	consumer.Provider = provider.CosmosChain

	relayerWallet, err := consumer.BuildRelayerWallet(ctx, "relayer-"+consumer.Config().ChainID)
	require.NoError(t, err)
	wallets := make([]ibc.Wallet, len(provider.Validators)+1)
	wallets[0] = relayerWallet
	for i := 1; i <= len(provider.Validators); i++ {
		wallets[i], err = consumer.BuildRelayerWallet(ctx, VALIDATOR_MONIKER)
		require.NoError(t, err)
	}
	walletAmounts := make([]ibc.WalletAmount, len(wallets))
	for i, wallet := range wallets {
		walletAmounts[i] = ibc.WalletAmount{
			Address: wallet.FormattedAddress(),
			Denom:   consumer.Config().Denom,
			Amount:  sdkmath.NewInt(VALIDATOR_FUNDS),
		}
	}
	ic := interchaintest.NewInterchain().
		AddChain(consumer.CosmosChain, walletAmounts...).
		AddRelayer(relayer, "relayer")

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})

	setupRelayerKeys(ctx, t, relayer, relayerWallet, consumer)
	rep := GetRelayerExecReporter(ctx)
	require.NoError(t, relayer.StopRelayer(ctx, rep))
	require.NoError(t, relayer.StartRelayer(ctx, rep))
	connectProviderConsumer(ctx, t, provider, consumer, relayer)

	for i, val := range consumer.Validators {
		require.NoError(t, val.RecoverKey(ctx, VALIDATOR_MONIKER, wallets[i+1].Mnemonic()))
	}

	return consumer
}

func createConsumerChainSpec(ctx context.Context, provider Chain, chainID, chainType, denom, version string, shouldCopyProviderKey []bool, spawnTime time.Time) *interchaintest.ChainSpec {
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

	modifyGenesis := cosmos.ModifyGenesis(genesisOverrides)
	if chainType == "stride" {
		genesisOverrides = append(genesisOverrides,
			cosmos.NewGenesisKV("app_state.gov.params.voting_period", "30s"),
		)
		modifyGenesis = func(cc ibc.ChainConfig, b []byte) ([]byte, error) {
			b, err := cosmos.ModifyGenesis(genesisOverrides)(cc, b)
			if err != nil {
				return nil, err
			}
			b, err = sjson.SetBytes(b, "app_state.epochs.epochs.#(identifier==\"day\").duration", "120s")
			if err != nil {
				return nil, err
			}
			return sjson.SetBytes(b, "app_state.epochs.epochs.#(identifier==\"stride_epoch\").duration", "30s")
		}
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
			GasAdjustment: 2.0,
			ChainID:       chainID,
			ConfigFileOverrides: map[string]any{
				"config/config.toml": createConfigToml(),
			},
			PreGenesis: func(cc ibc.ChainConfig) error {
				tCtx, tCancel := context.WithDeadline(ctx, spawnTime)
				defer tCancel()
				// interchaintest will set up the validator keys right before PreGenesis.
				// Now we just need to wait for the chain to spawn before interchaintest can get the ccv file.
				// This wait is here and not there because of changes we've made to interchaintest that need to be upstreamed in an orderly way.
				GetLogger(ctx).Sugar().Infof("waiting for chain %s to spawn at %s", chainID, spawnTime)
				<-tCtx.Done()
				return testutil.WaitForBlocks(ctx, 2, provider)
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
			ModifyGenesis: modifyGenesis,
			ConsumerCopyProviderKey: func(i int) bool {
				return shouldCopyProviderKey[i]
			},
		},
	}
}

func connectProviderConsumer(ctx context.Context, t *testing.T, provider Chain, consumer Chain, relayer ibc.Relayer) {
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

	require.Eventually(t, func() bool {
		providerTxChannel, err := GetTransferChannel(ctx, relayer, provider, consumer)
		return err == nil && providerTxChannel != nil
	}, 2*time.Minute, 10*time.Second)
}

func consumerAdditionProposal(ctx context.Context, t *testing.T, chainID string, provider Chain) time.Time {
	spawnTime := time.Now().Add(120 * time.Second)
	prop := ccvclient.ConsumerAdditionProposalJSON{
		Title:         fmt.Sprintf("Addition of %s consumer chain", chainID),
		Summary:       "Proposal to add new consumer chain",
		ChainId:       chainID,
		InitialHeight: clienttypes.Height{RevisionNumber: clienttypes.ParseChainID(chainID), RevisionHeight: 1},
		GenesisHash:   []byte("gen_hash"),
		BinaryHash:    []byte("bin_hash"),
		SpawnTime:     spawnTime,

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
	require.NoError(t, PassProposal(ctx, provider, propTx.ProposalID))
	return spawnTime
}
