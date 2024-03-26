package fresh_test

const (
	MNEMONIC_1      = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
	MNEMONIC_2      = "abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon cabbage abandon garage"
	VAL_FUNDS       = 11_000_000_000
	KEY_1           = "val1"
	KEY_2           = "val2"
	haltHeightDelta = int64(10)
)

// func TxTest(t *testing.T, ctx context.Context, wallet1, wallet2 ibc.Wallet, provider *cosmos.CosmosChain, consumer *cosmos.CosmosChain, relayer ibc.Relayer, eRep *testreporter.RelayerExecReporter) {
// 	addr1 := wallet1.FormattedAddress()
// 	addr2 := wallet2.FormattedAddress()

// 	// amusingly, upgrading the chain will result in the node returned from gaia.GetNode() being a different node
// 	// after upgrade than before, so we need to explicitly find the node with the key.
// 	var nodeWithKey *cosmos.ChainNode
// 	for _, node := range provider.Nodes() {
// 		if k, err := node.KeyBech32(ctx, wallet1.FormattedAddress(), ""); k != "" && err == nil {
// 			nodeWithKey = node
// 			break
// 		}
// 	}

// 	channels, err := relayer.GetChannels(ctx, eRep, provider.Config().ChainID)
// 	require.NoError(t, err)
// 	var providerChan *ibc.ChannelOutput
// 	for _, ch := range channels {
// 		if ch.PortID == "transfer" {
// 			providerChan = &ch
// 			break
// 		}
// 	}
// 	require.NotNil(t, providerChan)

// 	srcDenomTrace := transfertypes.ParseDenomTrace(transfertypes.GetPrefixedDenom("transfer", providerChan.Counterparty.ChannelID, provider.Config().Denom))
// 	dstIbcDenom := srcDenomTrace.IBCDenom()

// 	initial1, err := provider.GetBalance(ctx, addr1, "uatom")
// 	require.NoError(t, err)
// 	initial2, err := consumer.GetBalance(ctx, addr2, dstIbcDenom)
// 	require.NoError(t, err)

// 	amountToSend := math.NewInt(1_000_000)
// 	_, err = nodeWithKey.SendIBCTransfer(ctx, providerChan.ChannelID, wallet1.KeyName(), ibc.WalletAmount{
// 		Denom:   "uatom",
// 		Amount:  amountToSend,
// 		Address: addr2,
// 	}, ibc.TransferOptions{})
// 	require.NoError(t, err)

// 	time.Sleep(12 * time.Second)

// 	final1, err := provider.GetBalance(ctx, addr1, "uatom")
// 	require.NoError(t, err)
// 	final2, err := consumer.GetBalance(ctx, addr2, dstIbcDenom)
// 	require.NoError(t, err)

// 	require.Equal(t, initial2.Add(amountToSend), final2)
// 	require.True(t, final1.LTE(initial1.Sub(amountToSend)), "final1: %s, initial1 - amountToSend: %s", final1, initial1.Sub(amountToSend))

// }

// func BuildChains(t *testing.T, ctx context.Context) (*cosmos.CosmosChain, *cosmos.CosmosChain, ibc.Relayer, *testreporter.RelayerExecReporter) {
// 	configToml := make(testutil.Toml)
// 	consensusToml := make(testutil.Toml)
// 	consensusToml["timeout_commit"] = "10s"
// 	configToml["consensus"] = consensusToml
// 	configToml["block_sync"] = false
// 	configToml["fast_sync"] = false
// 	// There's an implementation detail in the chain object that means if this isn't 0, functions like UpgradeProposal will use the "full node" (i.e. non validator) instead of the validator.
// 	// This is actually changed in v8 and the validator is used for everything.
// 	fullNodes := 0
// 	cwd, err := os.Getwd()
// 	require.NoError(t, err)
// 	require.NoError(t, os.Setenv("IBCTEST_CONFIGURED_CHAINS", path.Join(cwd, "..", "configuredChains.yaml")))
// 	shortVoteGenesis := func(denom string) []cosmos.GenesisKV {
// 		return []cosmos.GenesisKV{
// 			cosmos.NewGenesisKV("app_state.gov.params.voting_period", "40s"),
// 			cosmos.NewGenesisKV("app_state.gov.params.max_deposit_period", "10s"),
// 			cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.denom", denom),
// 			cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.amount", "1"),
// 		}
// 	}

// 	cf := interchaintest.NewBuiltinChainFactory(
// 		zaptest.NewLogger(t),
// 		[]*interchaintest.ChainSpec{
// 			{
// 				Name:         "gaia",
// 				Version:      "v15.0.0-rc3",
// 				ChainName:    "provider",
// 				NumFullNodes: &fullNodes,
// 				ChainConfig: ibc.ChainConfig{
// 					Denom:         "uatom",
// 					GasPrices:     "0.005uatom",
// 					GasAdjustment: 2.0,
// 					ConfigFileOverrides: map[string]any{
// 						"config/config.toml": configToml,
// 					},
// 					ModifyGenesis: cosmos.ModifyGenesis(shortVoteGenesis("uatom")),
// 				},
// 			},
// 			{
// 				Name:         "stride",
// 				Version:      "v19.0.0",
// 				ChainName:    "consumer",
// 				NumFullNodes: &fullNodes,
// 				ChainConfig: ibc.ChainConfig{
// 					Denom:         "ucon",
// 					GasPrices:     "0.005ucon",
// 					GasAdjustment: 2.0,
// 					ConfigFileOverrides: map[string]any{
// 						"config/config.toml": configToml,
// 					},
// 				},
// 			},
// 		},
// 	)

// 	chains, err := cf.Chains(t.Name())
// 	require.NoError(t, err)
// 	provider, consumer := chains[0].(*cosmos.CosmosChain), chains[1].(*cosmos.CosmosChain)
// 	dockerClient, dockerNetwork := interchaintest.DockerSetup(t)

// 	f, err := interchaintest.CreateLogFile(fmt.Sprintf("%d.json", time.Now().Unix()))
// 	require.NoError(t, err)
// 	// Reporter/logs
// 	rep := testreporter.NewReporter(f)
// 	eRep := rep.RelayerExecReporter(t)

// 	relayer := interchaintest.NewBuiltinRelayerFactory(
// 		ibc.Hermes,
// 		zaptest.NewLogger(t),
// 	).Build(t, dockerClient, dockerNetwork)

// 	const relayerPath = "provider-2-consumer" // This isn't a concept in hermes, but interchaintest uses it internally

// 	ic := interchaintest.NewInterchain().
// 		AddChain(provider).
// 		AddChain(consumer).
// 		AddRelayer(relayer, "relayer").
// 		AddProviderConsumerLink(interchaintest.ProviderConsumerLink{
// 			Provider: provider,
// 			Consumer: consumer,
// 			Relayer:  relayer,
// 			Path:     relayerPath,
// 		})

// 	err = ic.Build(ctx, eRep, interchaintest.InterchainBuildOptions{
// 		Client:           dockerClient,
// 		NetworkID:        dockerNetwork,
// 		TestName:         t.Name(),
// 		SkipPathCreation: false,
// 	})
// 	require.NoError(t, err)
// 	t.Cleanup(func() {
// 		_ = ic.Close()
// 	})
// 	err = relayer.StartRelayer(ctx, eRep, relayerPath)
// 	require.NoError(t, err)
// 	t.Cleanup(func() {
// 		_ = relayer.StopRelayer(ctx, eRep)
// 	})

// 	return provider, consumer, relayer, eRep
// }

// func TestTransactions(t *testing.T) {
// 	ctx := context.Background()

// 	provider, consumer, relayer, eRep := BuildChains(t, ctx)
// 	time.Sleep(10 * time.Second)

// 	// wait for blocks in both chains
// 	timeoutCtx, timeoutCtxCancel := context.WithTimeout(ctx, time.Second*50)
// 	defer timeoutCtxCancel()
// 	err := testutil.WaitForBlocks(timeoutCtx, 5, provider, consumer)
// 	require.NoError(t, err, "error waiting for blocks")

// 	wallet1, err := interchaintest.GetAndFundTestUserWithMnemonic(ctx, KEY_1, MNEMONIC_1, math.NewInt(VAL_FUNDS), provider)
// 	require.NoError(t, err)
// 	wallet2, err := interchaintest.GetAndFundTestUserWithMnemonic(ctx, KEY_2, MNEMONIC_2, math.NewInt(VAL_FUNDS), consumer)
// 	require.NoError(t, err)

// 	TxTest(t, ctx, wallet1, wallet2, provider, consumer, relayer, eRep)
// }
