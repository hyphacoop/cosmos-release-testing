package fresh

import (
	"context"
	"fmt"
	"strconv"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/types"
	govv1beta1 "github.com/cosmos/cosmos-sdk/x/gov/types/v1beta1"
	clienttypes "github.com/cosmos/ibc-go/v7/modules/core/02-client/types"
	ccvclient "github.com/cosmos/interchain-security/v4/x/ccv/provider/client"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
	"github.com/tidwall/sjson"
	"golang.org/x/mod/semver"
)

type ConsumerBootstrapCb func(ctx context.Context, consumer *cosmos.CosmosChain)

type ConsumerConfig struct {
	ChainName             string
	Version               string
	Denom                 string
	ShouldCopyProviderKey [NUM_VALIDATORS]bool
	TopN                  int
	ValidatorSetCap       int
	ValidatorPowerCap     int

	DuringDepositPeriod ConsumerBootstrapCb
	DuringVotingPeriod  ConsumerBootstrapCb
	BeforeSpawnTime     ConsumerBootstrapCb
	AfterSpawnTime      ConsumerBootstrapCb
}

type proposalWaiter struct {
	canDeposit chan struct{}
	isInVoting chan struct{}
	canVote    chan struct{}
	isPassed   chan struct{}
}

func (pw *proposalWaiter) waitForDepositAllowed() {
	<-pw.canDeposit
}

func (pw *proposalWaiter) allowDeposit() {
	close(pw.canDeposit)
}

func (pw *proposalWaiter) waitForVotingPeriod() {
	<-pw.isInVoting
}

func (pw *proposalWaiter) startVotingPeriod() {
	close(pw.isInVoting)
}

func (pw *proposalWaiter) waitForVoteAllowed() {
	<-pw.canVote
}

func (pw *proposalWaiter) allowVote() {
	close(pw.canVote)
}

func (pw *proposalWaiter) waitForPassed() {
	<-pw.isPassed
}

func (pw *proposalWaiter) pass() {
	close(pw.isPassed)
}

func newProposalWaiter() *proposalWaiter {
	return &proposalWaiter{
		canDeposit: make(chan struct{}),
		isInVoting: make(chan struct{}),
		canVote:    make(chan struct{}),
		isPassed:   make(chan struct{}),
	}
}

func (p Chain) AddConsumerChain(ctx context.Context, t *testing.T, config ConsumerConfig) Chain {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	if len(config.ShouldCopyProviderKey) != NUM_VALIDATORS {
		panic(fmt.Sprintf("shouldCopyProviderKey must be the same length as the number of validators (%d)", NUM_VALIDATORS))
	}

	version := p.GetNode().GetBuildInformation(ctx).Version
	if (semver.Compare(version, "v17") >= 0 || !semver.IsValid(version)) && config.TopN < 0 {
		config.TopN = 95
	}

	spawnTime := time.Now().Add(CHAIN_SPAWN_WAIT)
	chainID := fmt.Sprintf("%s-%d", config.ChainName, len(p.Consumers)+1)

	proposalWaiter := p.consumerAdditionProposal(ctx, t, chainID, config, spawnTime)

	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{p.createConsumerChainSpec(ctx, chainID, config, spawnTime, proposalWaiter)},
	)
	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	consumer := Chain{chains[0].(*cosmos.CosmosChain), p.Relayer}

	// We can't use AddProviderConsumerLink here because the provider chain is already built; we'll have to do everything by hand.
	p.Consumers = append(p.Consumers, consumer.CosmosChain)
	consumer.Provider = p.CosmosChain

	relayerWallet, err := consumer.BuildRelayerWallet(ctx, "relayer-"+consumer.Config().ChainID)
	require.NoError(t, err)
	wallets := make([]ibc.Wallet, len(p.Validators)+1)
	wallets[0] = relayerWallet
	for i := 1; i <= len(p.Validators); i++ {
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
		AddRelayer(p.Relayer, "relayer")

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})

	setupRelayerKeys(ctx, t, p.Relayer, relayerWallet, consumer)
	rep := GetRelayerExecReporter(ctx)
	require.NoError(t, p.Relayer.StopRelayer(ctx, rep))
	require.NoError(t, p.Relayer.StartRelayer(ctx, rep))
	connectProviderConsumer(ctx, t, p, consumer, p.Relayer)

	for i, val := range consumer.Validators {
		require.NoError(t, val.RecoverKey(ctx, VALIDATOR_MONIKER, wallets[i+1].Mnemonic()))
	}
	return consumer
}

func (p Chain) createConsumerChainSpec(ctx context.Context, chainID string, config ConsumerConfig, spawnTime time.Time, proposalWaiter *proposalWaiter) *interchaintest.ChainSpec {
	fullNodes := NUM_FULL_NODES
	validators := NUM_VALIDATORS

	chainType := config.ChainName
	version := config.Version
	denom := config.Denom
	shouldCopyProviderKey := config.ShouldCopyProviderKey

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
	if config.TopN >= 0 {
		genesisOverrides = append(genesisOverrides, cosmos.NewGenesisKV("app_state.ccvconsumer.params.soft_opt_out_threshold", "0.0"))
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
			cosmos.NewGenesisKV("app_state.gov.params.voting_period", GOV_VOTING_PERIOD.String()),
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
	var providerVerOverride string

	if semver.Compare(p.GetNode().ICSVersion(ctx), "v4.1.0") > 0 {
		providerVerOverride = "v4.1.0"
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
			PreGenesis: func(consumer ibc.Chain) error {
				if config.DuringDepositPeriod != nil {
					config.DuringDepositPeriod(ctx, consumer.(*cosmos.CosmosChain))
				}
				proposalWaiter.allowDeposit()
				proposalWaiter.waitForVotingPeriod()
				if config.DuringVotingPeriod != nil {
					config.DuringVotingPeriod(ctx, consumer.(*cosmos.CosmosChain))
				}
				proposalWaiter.allowVote()
				proposalWaiter.waitForPassed()
				tCtx, tCancel := context.WithDeadline(ctx, spawnTime)
				defer tCancel()
				if config.BeforeSpawnTime != nil {
					config.BeforeSpawnTime(tCtx, consumer.(*cosmos.CosmosChain))
				}
				// interchaintest will set up the validator keys right before PreGenesis.
				// Now we just need to wait for the chain to spawn before interchaintest can get the ccv file.
				// This wait is here and not there because of changes we've made to interchaintest that need to be upstreamed in an orderly way.
				GetLogger(ctx).Sugar().Infof("waiting for chain %s to spawn at %s", chainID, spawnTime)
				<-tCtx.Done()
				if err := testutil.WaitForBlocks(ctx, 2, p); err != nil {
					return err
				}
				if config.AfterSpawnTime != nil {
					config.AfterSpawnTime(ctx, consumer.(*cosmos.CosmosChain))
				}
				return nil
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
			InterchainSecurityConfig: ibc.ICSConfig{
				ProviderVerOverride: providerVerOverride,
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

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		providerTxChannel, err := GetTransferChannel(ctx, relayer, provider, consumer)
		assert.NoError(c, err)
		assert.NotNil(c, providerTxChannel)
	}, 30*COMMIT_TIMEOUT, COMMIT_TIMEOUT)
}

func (p Chain) consumerAdditionProposal(ctx context.Context, t *testing.T, chainID string, config ConsumerConfig, spawnTime time.Time) *proposalWaiter {
	propWaiter := newProposalWaiter()
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
		Deposit:                           strconv.Itoa(GOV_MIN_DEPOSIT_AMOUNT/2) + DENOM,
	}
	if config.TopN >= 0 {
		prop.TopN = uint32(config.TopN)
	}
	if config.ValidatorSetCap > 0 {
		prop.ValidatorSetCap = uint32(config.ValidatorSetCap)
	}
	if config.ValidatorPowerCap > 0 {
		prop.ValidatorsPowerCap = uint32(config.ValidatorPowerCap)
	}
	propTx, err := p.ConsumerAdditionProposal(ctx, interchaintest.FaucetAccountKeyName, prop)
	require.NoError(t, err)
	go func() {
		require.NoError(t, p.WaitForProposalStatus(ctx, propTx.ProposalID, govv1beta1.StatusDepositPeriod))
		propWaiter.waitForDepositAllowed()

		_, err = p.GetNode().ExecTx(ctx, VALIDATOR_MONIKER, "gov", "deposit", propTx.ProposalID, prop.Deposit)
		require.NoError(t, err)

		require.NoError(t, p.WaitForProposalStatus(ctx, propTx.ProposalID, govv1beta1.StatusVotingPeriod))
		propWaiter.startVotingPeriod()
		propWaiter.waitForVoteAllowed()

		require.NoError(t, p.PassProposal(ctx, propTx.ProposalID))
		propWaiter.pass()
	}()
	return propWaiter
}

func isValoperJailed(ctx context.Context, t *testing.T, provider Chain, valoper string) bool {
	out, _, err := provider.Validators[0].ExecQuery(ctx, "staking", "validator", valoper)
	require.NoError(t, err)
	if gjson.GetBytes(out, "jailed").Exists() {
		return gjson.GetBytes(out, "jailed").Bool()
	}
	return gjson.GetBytes(out, "validator.jailed").Bool()
}

func CheckIfValidatorJailed(ctx context.Context, t *testing.T, provider, consumer Chain, validatorIdx int, shouldJail bool) {
	require.NoError(t, consumer.Validators[validatorIdx].StopContainer(ctx))
	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	valoper := wallets[validatorIdx].ValoperAddress
	if shouldJail {
		require.Eventuallyf(t, func() bool {
			return isValoperJailed(ctx, t, provider, valoper)
		}, 30*COMMIT_TIMEOUT, COMMIT_TIMEOUT, "validator %d never jailed", validatorIdx)

		require.NoError(t, consumer.Validators[validatorIdx].StartContainer(ctx))
		time.Sleep(10 * COMMIT_TIMEOUT)
		_, err = provider.Validators[validatorIdx].ExecTx(ctx, wallets[validatorIdx].Moniker, "slashing", "unjail")
		require.NoError(t, err)
		require.False(t, isValoperJailed(ctx, t, provider, valoper), "validator %d not unjailed", validatorIdx)
	} else {
		require.Neverf(t, func() bool {
			return isValoperJailed(ctx, t, provider, valoper)
		}, 30*COMMIT_TIMEOUT, COMMIT_TIMEOUT, "validator %d jailed", validatorIdx)
		require.NoError(t, consumer.Validators[validatorIdx].StartContainer(ctx))
		time.Sleep(10 * COMMIT_TIMEOUT)
	}
}

func RSValidatorsJailedTest(ctx context.Context, t *testing.T, provider Chain, consumer Chain) {
	const (
		lastValidator       = NUM_VALIDATORS - 1
		secondLastValidator = NUM_VALIDATORS - 2
	)
	CheckIfValidatorJailed(ctx, t, provider, consumer, lastValidator, false)
	CheckIfValidatorJailed(ctx, t, provider, consumer, secondLastValidator, true)
}

func GetPower(ctx context.Context, chain Chain, hexaddr string) (int64, error) {
	var power int64
	err := CheckEndpoint(ctx, chain.GetHostRPCAddress()+"/validators", func(b []byte) error {
		power = gjson.GetBytes(b, fmt.Sprintf("result.validators.#(address==\"%s\").voting_power", hexaddr)).Int()
		if power == 0 {
			return fmt.Errorf("validator %s power not found; validators are: %s", hexaddr, string(b))
		}
		return nil
	})
	if err != nil {
		return 0, err
	}
	return power, nil
}

func DelegateToValidator(ctx context.Context, t *testing.T, provider, consumer Chain, amount, valIdx, blocksPerEpoch int) {
	wallets, err := GetValidatorWallets(ctx, provider)
	require.NoError(t, err)
	providerAddress := wallets[valIdx]

	json, err := provider.Validators[valIdx].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	providerHex := gjson.GetBytes(json, "address").String()
	json, err = consumer.Validators[valIdx].ReadFile(ctx, "config/priv_validator_key.json")
	require.NoError(t, err)
	consumerHex := gjson.GetBytes(json, "address").String()

	providerPowerBefore, err := GetPower(ctx, provider, providerHex)
	require.NoError(t, err)

	_, err = provider.Validators[valIdx].ExecTx(ctx, providerAddress.Moniker,
		"staking", "delegate",
		providerAddress.ValoperAddress, fmt.Sprintf("%d%s", amount, DENOM),
	)
	require.NoError(t, err)

	if blocksPerEpoch > 1 {
		providerPower, err := GetPower(ctx, provider, providerHex)
		require.NoError(t, err)
		require.Greater(t, providerPower, providerPowerBefore)
		consumerPower, err := GetPower(ctx, consumer, consumerHex)
		require.NotEqual(t, providerPower, consumerPower)
		require.NoError(t, testutil.WaitForBlocks(ctx, blocksPerEpoch, provider))
	}

	require.EventuallyWithT(t, func(c *assert.CollectT) {
		providerPower, err := GetPower(ctx, provider, providerHex)
		assert.NoError(c, err)
		consumerPower, err := GetPower(ctx, consumer, consumerHex)
		assert.NoError(c, err)
		assert.Greater(c, providerPower, providerPowerBefore)
		assert.Equal(c, providerPower, consumerPower)
	}, 15*time.Minute, COMMIT_TIMEOUT)
}

func CCVKeyAssignmentTest(ctx context.Context, t *testing.T, provider, consumer Chain, relayer ibc.Relayer, blocksPerEpoch int) {
	DelegateToValidator(ctx, t, provider, consumer, VALIDATOR_STAKE_STEP, 0, blocksPerEpoch)
}
