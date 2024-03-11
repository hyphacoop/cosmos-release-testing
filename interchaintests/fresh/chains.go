package fresh

import (
	"context"
	"os"
	"path"
	"strconv"
	"sync"
	"testing"
	"time"

	sdkmath "cosmossdk.io/math"
	"github.com/cosmos/cosmos-sdk/types"
	govv1beta1 "github.com/cosmos/cosmos-sdk/x/gov/types/v1beta1"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

type ValidatorWallet struct {
	Moniker        string
	Address        string
	ValoperAddress string
}

func CreateChains(ctx context.Context, t *testing.T, gaiaVersion string) *cosmos.CosmosChain {
	// TODO: allow creation of consumer chains
	configToml := make(testutil.Toml)
	consensusToml := make(testutil.Toml)
	consensusToml["timeout_commit"] = "10s"
	configToml["consensus"] = consensusToml
	configToml["block_sync"] = false
	configToml["fast_sync"] = false
	fullNodes := 0
	validators := 3
	cwd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Setenv("IBCTEST_CONFIGURED_CHAINS", path.Join(cwd, "..", "configuredChains.yaml")))
	shortVoteGenesis := func(denom string) []cosmos.GenesisKV {
		return []cosmos.GenesisKV{
			cosmos.NewGenesisKV("app_state.gov.params.voting_period", "40s"),
			cosmos.NewGenesisKV("app_state.gov.params.max_deposit_period", "10s"),
			cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.denom", denom),
			cosmos.NewGenesisKV("app_state.gov.params.min_deposit.0.amount", "1"),
		}
	}

	cf := interchaintest.NewBuiltinChainFactory(
		GetLogger(ctx),
		[]*interchaintest.ChainSpec{
			{
				Name:          "gaia",
				Version:       gaiaVersion,
				ChainName:     "provider",
				NumFullNodes:  &fullNodes,
				NumValidators: &validators,
				ChainConfig: ibc.ChainConfig{
					Denom:         DENOM,
					GasPrices:     "0.005" + DENOM,
					GasAdjustment: 2.0,
					ConfigFileOverrides: map[string]any{
						"config/config.toml": configToml,
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
					ModifyGenesis: cosmos.ModifyGenesis(shortVoteGenesis(DENOM)),
				},
			},
		},
	)

	chains, err := cf.Chains(t.Name())
	require.NoError(t, err)
	provider := chains[0].(*cosmos.CosmosChain)
	dockerClient, dockerNetwork := interchaintest.DockerSetup(t)

	ic := interchaintest.NewInterchain().
		AddChain(provider)

	err = ic.Build(ctx, GetRelayerExecReporter(ctx), interchaintest.InterchainBuildOptions{
		Client:           dockerClient,
		NetworkID:        dockerNetwork,
		TestName:         t.Name(),
		SkipPathCreation: false,
	})
	require.NoError(t, err)
	t.Cleanup(func() {
		_ = ic.Close()
	})
	return provider
}

func UpgradeChain(ctx context.Context, t *testing.T, chain *cosmos.CosmosChain, proposalKey, upgradeName, version string) {
	height, err := chain.Height(ctx)
	require.NoError(t, err, "error fetching height before submit upgrade proposal")

	haltHeight := height + UPGRADE_DELTA

	proposal := cosmos.SoftwareUpgradeProposal{
		Deposit:     "5000000uatom", // greater than min deposit
		Title:       "Upgrade to " + upgradeName,
		Name:        upgradeName,
		Description: "Upgrade to " + upgradeName,
		Height:      haltHeight,
	}
	upgradeTx, err := chain.UpgradeProposal(ctx, proposalKey, proposal)
	require.NoError(t, err, "error submitting upgrade proposal")
	propId, err := strconv.Atoi(upgradeTx.ProposalID)
	require.NoError(t, err, "error converting proposal id to int")

	err = chain.VoteOnProposalAllValidators(ctx, int64(propId), cosmos.ProposalVoteYes)
	require.NoError(t, err, "error voting on upgrade proposal")
	prop, err := cosmos.PollForProposalStatus(ctx, chain, height, haltHeight, int64(propId), govv1beta1.StatusPassed)
	require.NoError(t, err, "error polling for proposal status: %+v", prop)

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

func GetValidatorWallets(ctx context.Context, chain *cosmos.CosmosChain) ([]ValidatorWallet, error) {
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
