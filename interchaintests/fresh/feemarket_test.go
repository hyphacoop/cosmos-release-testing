package fresh_test

import (
	"context"
	"encoding/json"
	"fmt"
	"path"
	"strconv"
	"testing"
	"time"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/sjson"
	"golang.org/x/sync/errgroup"
)

func TestFeeMarket(t *testing.T) {
	const (
		txsPerBlock         = 600
		blocksToPack        = 5
		maxBlockUtilization = 1000000
	)
	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	chain := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)
	fresh.UpgradeChain(ctx, t, chain, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	setMaxBlockUtilization(ctx, t, chain, maxBlockUtilization)

	setCommitTimeout(ctx, t, chain, 130*time.Second)

	packBlocks(ctx, t, chain, txsPerBlock, blocksToPack)
}

func setMaxBlockUtilization(ctx context.Context, t *testing.T, chain fresh.Chain, utilization int) {
	params, _, err := chain.GetNode().ExecQuery(ctx, "feemarket", "params")
	require.NoError(t, err)

	params, err = sjson.SetBytes(params, "max_block_utilization", fmt.Sprint(utilization))
	require.NoError(t, err)

	govAuthority, err := chain.GetGovernanceAddress(ctx)
	require.NoError(t, err)

	proposalJson := fmt.Sprintf(`{
		"@type": "/feemarket.feemarket.v1.MsgParams",
		"authority": "%s"
}`, govAuthority)
	proposalJson, err = sjson.SetRaw(proposalJson, "params", string(params))
	require.NoError(t, err)

	txhash, err := chain.GetNode().SubmitProposal(ctx, fresh.VALIDATOR_MONIKER,
		cosmos.TxProposalv1{
			Title:    "Set Block Params",
			Deposit:  fresh.GOV_DEPOSIT_AMOUNT,
			Messages: []json.RawMessage{json.RawMessage(proposalJson)},
			Summary:  "Set Block Params",
			Metadata: "ipfs://CID",
		})
	require.NoError(t, err)

	propId, err := fresh.GetProposalID(ctx, chain, txhash)
	require.NoError(t, err)
	require.NoError(t, chain.PassProposal(ctx, propId))
	maxBlock := chain.QueryJSON(ctx, t, "max_block_utilization", "feemarket", "params").String()
	require.NoError(t, err)
	require.Equal(t, fmt.Sprint(utilization), maxBlock)

}

func packBlocks(ctx context.Context, t *testing.T, chain fresh.Chain, txsPerBlock, blocksToPack int) {
	script := `
#!/bin/sh

set -ue
set -o pipefail

TX_COUNT=$1
CHAIN_BINARY=$2
FROM=$3
TO=$4
DENOM=$5
GAS_PRICES=$6
CHAIN_ID=$7
VAL_HOME=$8
NODE=$9

i=0

SEQUENCE=$($CHAIN_BINARY query account $FROM --chain-id $CHAIN_ID --node $NODE --home $VAL_HOME -o json | jq -r .sequence)
ACCOUNT=$($CHAIN_BINARY query account $FROM --chain-id $CHAIN_ID --node $NODE --home $VAL_HOME -o json | jq -r .account_number)

$CHAIN_BINARY tx bank send $FROM $TO 1$DENOM --keyring-backend test --generate-only --account-number $ACCOUNT --from $FROM --chain-id $CHAIN_ID --gas 500000 --gas-adjustment 2.0 --gas-prices $GAS_PRICES$DENOM --home $VAL_HOME --node $NODE -o json > tx.json

while [ $i -lt $TX_COUNT ]; do
	$CHAIN_BINARY tx sign tx.json --from $FROM --chain-id $CHAIN_ID --sequence $SEQUENCE --keyring-backend test --account-number $ACCOUNT --offline --home $VAL_HOME > tx.json.signed
	tx=$($CHAIN_BINARY tx broadcast tx.json.signed --node $NODE --chain-id $CHAIN_ID --home $VAL_HOME -o json)
	if [ $(echo $tx | jq -r .code) -ne 0 ]; then
		echo "$tx" >&2
		$CHAIN_BINARY query tx $(echo $tx | jq -r .txhash) --chain-id $CHAIN_ID --node $NODE --home $VAL_HOME >&2
		exit 1
	else
		echo $(echo $tx | jq -r .txhash)
	fi
	SEQUENCE=$((SEQUENCE+1))
	i=$((i+1))
done
`
	for _, val := range chain.Validators {
		err := val.WriteFile(ctx, []byte(script), "pack.sh")
		require.NoError(t, err)
	}
	wallets, err := fresh.GetValidatorWallets(ctx, chain)
	require.NoError(t, err)

	gasStr := chain.QueryJSON(ctx, t, "price.amount", "feemarket", "gas-price", chain.Config().Denom).String()
	gasBefore, err := strconv.ParseFloat(gasStr, 64)
	require.NoError(t, err)
	gasNow := gasBefore

	require.NoError(t, testutil.WaitForBlocks(ctx, 1, chain))

	prevBlock, err := chain.Height(ctx)
	require.NoError(t, err)

	for i := 0; i < blocksToPack; i++ {
		eg := errgroup.Group{}
		for v, val := range chain.Validators {
			val := val
			v := v
			eg.Go(func() error {
				_, stderr, err := val.Exec(ctx, []string{
					"sh", path.Join(val.HomeDir(), "pack.sh"),
					strconv.Itoa(txsPerBlock / len(chain.Validators)),
					chain.Config().Bin,
					wallets[v].Address,
					wallets[(v+1)%len(chain.Validators)].Address,
					chain.Config().Denom,
					fmt.Sprint(gasNow),
					chain.Config().ChainID,
					val.HomeDir(),
					fmt.Sprintf("tcp://%s:26657", val.HostName()),
				}, nil)

				if err != nil {
					return fmt.Errorf("err %w, stderr: %s", err, stderr)
				} else if len(stderr) > 0 {
					return fmt.Errorf("stderr: %s", stderr)
				}
				return nil
			})
		}
		require.NoError(t, eg.Wait())
		require.NoError(t, testutil.WaitForBlocks(ctx, 1, chain))
		time.Sleep(5 * time.Second) // ensure the feemarket has time to update
		currentBlock, err := chain.Height(ctx)
		require.NoError(t, err)
		require.Equal(t, prevBlock+1, currentBlock)
		prevBlock = currentBlock

		gasStr = chain.QueryJSON(ctx, t, "price.amount", "feemarket", "gas-price", chain.Config().Denom).String()
		gasNow, err = strconv.ParseFloat(gasStr, 64)
		require.NoError(t, err)
		require.Greater(t, gasNow, gasBefore)
		gasBefore = gasNow
	}
}

func setCommitTimeout(ctx context.Context, t *testing.T, chain fresh.Chain, timeout time.Duration) {
	eg := errgroup.Group{}
	for _, val := range chain.Validators {
		val := val
		eg.Go(func() error {
			configToml := make(testutil.Toml)
			consensusToml := make(testutil.Toml)
			consensusToml["timeout_commit"] = timeout.String()
			configToml["consensus"] = consensusToml
			if err := testutil.ModifyTomlConfigFile(
				ctx, fresh.GetLogger(ctx),
				val.DockerClient, t.Name(), val.VolumeName,
				"config/config.toml", configToml,
			); err != nil {
				return err
			}
			if err := val.StopContainer(ctx); err != nil {
				return err
			}
			return val.StartContainer(ctx)
		})
	}
	require.NoError(t, eg.Wait())
	require.NoError(t, testutil.WaitForBlocks(ctx, 1, chain))
}
