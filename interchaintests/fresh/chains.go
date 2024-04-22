package fresh

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/types"
	govv1beta1 "github.com/cosmos/cosmos-sdk/x/gov/types/v1beta1"
	"github.com/cosmos/cosmos-sdk/x/params/client/utils"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/relayer"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
	"golang.org/x/sync/errgroup"
)

type ValidatorWallet struct {
	Moniker        string
	Address        string
	ValoperAddress string
}

type Chain struct {
	*cosmos.CosmosChain
}

func (c Chain) QueryJSON(ctx context.Context, t *testing.T, path string, query ...string) gjson.Result {
	t.Helper()
	stdout, _, err := c.GetNode().ExecQuery(ctx, query...)
	require.NoError(t, err)
	retval := gjson.GetBytes(stdout, path)
	require.True(t, retval.Exists(), "path %s does not exist in %s", path, stdout)
	return retval
}

func createConfigToml() testutil.Toml {
	configToml := make(testutil.Toml)
	consensusToml := make(testutil.Toml)
	consensusToml["timeout_commit"] = COMMIT_TIMEOUT.String()
	configToml["consensus"] = consensusToml
	configToml["block_sync"] = false
	configToml["fast_sync"] = false
	return configToml
}

func createGaiaChainSpec(ctx context.Context, chainName, gaiaVersion string) *interchaintest.ChainSpec {
	fullNodes := 0
	validators := 3
	genesisOverrides := []cosmos.GenesisKV{
		cosmos.NewGenesisKV("app_state.gov.params.voting_period", "40s"),
		cosmos.NewGenesisKV("app_state.gov.params.max_deposit_period", "10s"),
		cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.denom", DENOM),
		cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.amount", "1"),
		cosmos.NewGenesisKV("app_state.slashing.params.signed_blocks_window", strconv.Itoa(SLASHING_WINDOW_PROVIDER)),
		cosmos.NewGenesisKV("app_state.slashing.params.downtime_jail_duration", DOWNTIME_JAIL_DURATION.String()),
	}
	return &interchaintest.ChainSpec{
		Name:          "gaia",
		Version:       gaiaVersion,
		ChainName:     chainName,
		NumFullNodes:  &fullNodes,
		NumValidators: &validators,
		ChainConfig: ibc.ChainConfig{
			Denom:         DENOM,
			GasPrices:     "0.005" + DENOM,
			GasAdjustment: 2.0,
			ConfigFileOverrides: map[string]any{
				"config/config.toml": createConfigToml(),
			},
			Images: []ibc.DockerImage{{
				Repository: GetConfig(ctx).DockerRepository,
				UidGid:     "1025:1025", // this is the user in heighliner docker images
			}},
			ModifyGenesisAmounts: func(i int) (types.Coin, types.Coin) {
				return types.Coin{
						Amount: sdkmath.NewInt(VALIDATOR_FUNDS),
						Denom:  DENOM,
					}, types.Coin{
						Amount: sdkmath.NewInt(getValidatorStake()[i]),
						Denom:  DENOM,
					}
			},
			ModifyGenesis: cosmos.ModifyGenesis(genesisOverrides),
		},
	}
}

func createRelayer(ctx context.Context, t *testing.T) ibc.Relayer {
	dockerClient, dockerNetwork := GetDockerContext(ctx)
	return interchaintest.NewBuiltinRelayerFactory(
		ibc.Hermes, // TODO: allow specifying relayer type
		GetLogger(ctx),
		relayer.CustomDockerImage("ghcr.io/informalsystems/hermes", "v1.8.0", "1000:1000"),
	).Build(t, dockerClient, dockerNetwork)
}

// CreateLinkedChains creates two new chains with the given version, links them through IBC, and returns the chain and relayer objects.
func CreateLinkedChains(ctx context.Context, t *testing.T, gaiaVersion, channelVersion string) (Chain, Chain, ibc.Relayer) {
	chains, relayer := CreateNLinkedChains(ctx, t, gaiaVersion, channelVersion, 2)
	return chains[0], chains[1], relayer
}

func CreateNLinkedChains(ctx context.Context, t *testing.T, gaiaVersion, channelVersion string, n int) ([]Chain, ibc.Relayer) {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	chainspecs := make([]*interchaintest.ChainSpec, n)
	for i := 0; i < n; i++ {
		chainspecs[i] = createGaiaChainSpec(ctx, fmt.Sprintf("gaia-%d", i), gaiaVersion)
	}
	cf := interchaintest.NewBuiltinChainFactory(GetLogger(ctx), chainspecs)
	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	relayer := createRelayer(ctx, t)
	retval := make([]Chain, n)
	for i := 0; i < n; i++ {
		retval[i] = Chain{chains[i].(*cosmos.CosmosChain)}
	}

	ic := interchaintest.NewInterchain()
	ic.AddRelayer(relayer, "relayer")
	for _, chain := range retval {
		ic.AddChain(chain.CosmosChain)
	}
	for i := 0; i < n-1; i++ {
		chainA := retval[i]
		chainB := retval[i+1]
		ic.AddLink(interchaintest.InterchainLink{
			Chain1:  chainA.CosmosChain,
			Chain2:  chainB.CosmosChain,
			Relayer: relayer,
			Path:    RelayerTransferPathFor(chainA, chainB),
			CreateChannelOpts: ibc.CreateChannelOptions{
				DestPortName:   TRANSFER_PORT_ID,
				SourcePortName: TRANSFER_PORT_ID,
				Version:        channelVersion,
				Order:          ibc.Unordered,
			},
		})
	}

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})

	require.NoError(t, relayer.StartRelayer(ctx, GetRelayerExecReporter(ctx)))
	t.Cleanup(func() {
		_ = relayer.StopRelayer(ctx, GetRelayerExecReporter(ctx))
	})
	return retval, relayer
}

// CreateChain creates a single new chain with the given version and returns the chain object.
func CreateChain(ctx context.Context, t *testing.T, gaiaVersion string, withRelayer bool) (Chain, ibc.Relayer) {
	dockerClient, dockerNetwork := GetDockerContext(ctx)

	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{createGaiaChainSpec(ctx, "gaia", gaiaVersion)},
	)

	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	provider := Chain{chains[0].(*cosmos.CosmosChain)}
	var relayer ibc.Relayer
	var relayerWallet ibc.Wallet

	ic := interchaintest.NewInterchain()

	if withRelayer {
		relayer = createRelayer(ctx, t)
		ic.AddRelayer(relayer, "relayer")
		relayerWallet, err = provider.BuildRelayerWallet(ctx, "relayer-"+provider.Config().ChainID)
		require.NoError(t, err)
		ic.AddChain(provider.CosmosChain, ibc.WalletAmount{
			Address: relayerWallet.FormattedAddress(),
			Denom:   provider.Config().Denom,
			Amount:  sdkmath.NewInt(VALIDATOR_FUNDS),
		})
	} else {
		ic.AddChain(provider.CosmosChain)
	}

	require.NoError(t, ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:    dockerClient,
		NetworkID: dockerNetwork,
		TestName:  t.Name(),
	}))
	t.Cleanup(func() {
		_ = ic.Close()
	})
	if withRelayer {
		setupRelayerKeys(ctx, t, relayer, relayerWallet, provider)
		require.NoError(t, relayer.StartRelayer(ctx, GetRelayerExecReporter(ctx)))
		t.Cleanup(func() {
			_ = relayer.StopRelayer(ctx, GetRelayerExecReporter(ctx))
		})
	}
	return provider, relayer
}

func PassProposal(ctx context.Context, chain Chain, proposalID string) error {
	propID, err := strconv.ParseInt(proposalID, 10, 64)
	if err != nil {
		return err
	}
	err = chain.VoteOnProposalAllValidators(ctx, propID, cosmos.ProposalVoteYes)
	if err != nil {
		return err
	}
	chainHeight, err := chain.Height(ctx)
	if err != nil {
		return err
	}
	maxHeight := chainHeight + UPGRADE_DELTA
	_, err = cosmos.PollForProposalStatus(ctx, chain.CosmosChain, chainHeight, maxHeight, propID, govv1beta1.StatusPassed)
	return err
}

func UpgradeChain(ctx context.Context, t *testing.T, chain Chain, proposalKey, upgradeName, version string) {
	height, err := chain.Height(ctx)
	require.NoError(t, err, "error fetching height before submit upgrade proposal")

	haltHeight := height + UPGRADE_DELTA

	proposal := cosmos.SoftwareUpgradeProposal{
		Deposit:     GOV_DEPOSIT_AMOUNT, // greater than min deposit
		Title:       "Upgrade to " + upgradeName,
		Name:        upgradeName,
		Description: "Upgrade to " + upgradeName,
		Height:      haltHeight,
	}
	upgradeTx, err := chain.UpgradeProposal(ctx, proposalKey, proposal)
	require.NoError(t, err, "error submitting upgrade proposal")
	require.NoError(t, PassProposal(ctx, chain, upgradeTx.ProposalID))

	height, err = chain.Height(ctx)
	require.NoError(t, err, "error fetching height after upgrade proposal passed")

	// wait for the chain to halt. We're asking for one more block than the halt height, so we should time out.
	timeoutCtx, timeoutCtxCancel := context.WithTimeout(ctx, time.Second*60)
	defer timeoutCtxCancel()
	err = testutil.WaitForBlocks(timeoutCtx, int(haltHeight-height)+1, chain)
	require.Error(t, err, "chain should not produce blocks after halt height")

	height, err = chain.Height(ctx)
	require.NoError(t, err, "error fetching height after chain should have halted")

	// make sure that chain is halted
	require.Equal(t, haltHeight, height, "height is not equal to halt height")

	// bring down nodes to prepare for upgrade
	err = chain.StopAllNodes(ctx)
	require.NoError(t, err, "error stopping node(s)")

	// upgrade version on all nodes
	chain.UpgradeVersion(ctx, chain.GetNode().DockerClient, chain.GetNode().Image.Repository, version)

	// start all nodes back up.
	// validators reach consensus on first block after upgrade height
	// and chain block production resumes.
	err = chain.StartAllNodes(ctx)
	require.NoError(t, err, "error starting upgraded node(s)")

	timeoutCtx, timeoutCancel := context.WithTimeout(ctx, 60*time.Second)
	defer timeoutCancel()
	err = testutil.WaitForBlocks(timeoutCtx, 5, chain)
	require.NoError(t, err)

	// Flush "successfully migrated key info" messages
	for _, val := range chain.Validators {
		_, _, err := val.ExecBin(ctx, "keys", "list", "--keyring-backend", "test")
		require.NoError(t, err)
	}
}

func GetChannelWithPort(ctx context.Context, relayer ibc.Relayer, chain, counterparty Chain, portID string) (*ibc.ChannelOutput, error) {
	clients, err := relayer.GetClients(ctx, GetRelayerExecReporter(ctx), chain.Config().ChainID)
	if err != nil {
		return nil, err
	}
	var client *ibc.ClientOutput
	for _, c := range clients {
		if c.ClientState.ChainID == counterparty.Config().ChainID {
			client = c
			break
		}
	}
	if client == nil {
		return nil, fmt.Errorf("no client found for chain %s", counterparty.Config().ChainID)
	}

	stdout, _, err := chain.GetNode().ExecQuery(ctx, "ibc", "connection", "connections")
	if err != nil {
		return nil, fmt.Errorf("error querying connections: %w", err)
	}
	connections := gjson.GetBytes(stdout, fmt.Sprintf("connections.#(client_id==\"%s\")#.id", client.ClientID)).Array()
	if len(connections) == 0 {
		return nil, fmt.Errorf("no connections found for client %s", client.ClientID)
	}
	for _, connID := range connections {
		stdout, _, err := chain.GetNode().ExecQuery(ctx, "ibc", "channel", "connections", connID.String())
		if err != nil {
			return nil, err
		}
		channelJson := gjson.GetBytes(stdout, fmt.Sprintf("channels.#(port_id==\"%s\")", portID)).String()
		if channelJson != "" {
			channelOutput := &ibc.ChannelOutput{}
			if err := json.Unmarshal([]byte(channelJson), channelOutput); err != nil {
				return nil, fmt.Errorf("error unmarshalling channel output %s: %w", channelJson, err)
			}
			return channelOutput, nil
		}
	}
	return nil, fmt.Errorf("no channel found for port %s", portID)
}

func GetTransferChannel(ctx context.Context, relayer ibc.Relayer, chain, counterparty Chain) (*ibc.ChannelOutput, error) {
	return GetChannelWithPort(ctx, relayer, chain, counterparty, TRANSFER_PORT_ID)
}

func GetValidatorWallets(ctx context.Context, chain Chain) ([]ValidatorWallet, error) {
	wallets := make([]ValidatorWallet, NUM_VALIDATORS)
	lock := new(sync.Mutex)
	eg := new(errgroup.Group)
	for i := 0; i < NUM_VALIDATORS; i++ {
		i := i
		eg.Go(func() error {
			// This moniker is hardcoded into the chain's genesis process.
			moniker := VALIDATOR_MONIKER
			address, err := chain.Validators[i].KeyBech32(ctx, moniker, "acc")
			if err != nil {
				return err
			}
			valoperAddress, err := chain.Validators[i].KeyBech32(ctx, moniker, "val")
			if err != nil {
				return err
			}
			lock.Lock()
			defer lock.Unlock()
			wallets[i] = ValidatorWallet{
				Moniker:        moniker,
				Address:        address,
				ValoperAddress: valoperAddress,
			}
			return nil
		})
	}
	if err := eg.Wait(); err != nil {
		return nil, err
	}
	return wallets, nil
}

func SetEpoch(ctx context.Context, chain Chain, epoch int) error {
	result, err := chain.ParamChangeProposal(ctx, VALIDATOR_MONIKER, &utils.ParamChangeProposalJSON{
		Changes: []utils.ParamChangeJSON{{
			Subspace: "provider",
			Key:      "BlocksPerEpoch",
			Value:    json.RawMessage(fmt.Sprintf("\"%d\"", epoch)),
		}},
		Title:       fmt.Sprintf("Set blocks per epoch to %d", epoch),
		Description: fmt.Sprintf("Set blocks per epoch to %d", epoch),
		Deposit:     GOV_DEPOSIT_AMOUNT,
	})
	if err != nil {
		return err
	}
	return PassProposal(ctx, chain, result.ProposalID)
}
