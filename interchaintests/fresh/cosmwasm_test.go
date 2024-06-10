package fresh_test

import (
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/hyphacoop/cosmos-release-testing/interchaintests/fresh"
	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/stretchr/testify/require"
)

func TestWasm(t *testing.T) {
	const (
		initState = `{"count": 100}`
		query     = `{"get_count":{}}`
		increment = `{"increment":{}}`
	)

	ctx, err := fresh.NewTestContext(t)
	require.NoError(t, err)

	chain := fresh.CreateChain(ctx, t, fresh.GetConfig(ctx).StartVersion, false)
	fresh.UpgradeChain(ctx, t, chain, fresh.GetConfig(ctx).TargetVersion, fresh.GetConfig(ctx).UpgradeVersion)

	contractWasm, err := os.ReadFile("testdata/contract.wasm")
	require.NoError(t, err)

	require.NoError(t, chain.GetNode().WriteFile(ctx, contractWasm, "contract.wasm"))
	contractPath := path.Join(chain.GetNode().HomeDir(), "contract.wasm")

	govAddr, err := chain.GetGovernanceAddress(ctx)
	require.NoError(t, err)

	codeCountBefore := len(chain.QueryJSON(ctx, t, "code_infos", "wasm", "list-code").Array())

	_, err = chain.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"wasm", "store", contractPath,
	)
	require.Error(t, err)

	codeCountAfter := len(chain.QueryJSON(ctx, t, "code_infos", "wasm", "list-code").Array())
	require.Equal(t, codeCountBefore, codeCountAfter)

	txhash, err := chain.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"wasm", "submit-proposal", "store-instantiate",
		contractPath,
		initState, "--label", "my-contract",
		"--no-admin", "--instantiate-nobody", "true",
		"--title", "Store and instantiate template",
		"--summary", "Store and instantiate template",
		"--deposit", fmt.Sprintf("10000000%s", fresh.DENOM),
	)
	require.NoError(t, err)

	proposalId, err := fresh.GetProposalID(ctx, chain, txhash)
	require.NoError(t, err)

	err = chain.PassProposal(ctx, proposalId)
	require.NoError(t, err)

	code := chain.QueryJSON(ctx, t, fmt.Sprintf("code_infos.#(creator=\"%s\").code_id", govAddr), "wasm", "list-code").String()

	contractAddr := chain.QueryJSON(ctx, t, "contracts.0", "wasm", "list-contract-by-code", code).String()

	_, err = chain.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"wasm", "instantiate", code, initState, "--label", "my-contract", "--no-admin",
	)
	require.Error(t, err)

	count := chain.QueryJSON(ctx, t, "data.count", "wasm", "contract-state", "smart", contractAddr, query).Int()
	require.Equal(t, int64(100), count)

	_, err = chain.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"wasm", "execute", contractAddr, increment,
	)
	require.NoError(t, err)

	countAfter := chain.QueryJSON(ctx, t, "data.count", "wasm", "contract-state", "smart", contractAddr, query).Int()
	require.Equal(t, int64(101), countAfter)

	txhash, err = chain.GetNode().ExecTx(ctx, interchaintest.FaucetAccountKeyName,
		"wasm", "submit-proposal", "execute-contract",
		contractAddr, increment,
		"--title", "Increment count",
		"--summary", "Increment count",
		"--deposit", fmt.Sprintf("1000000%s", fresh.DENOM),
	)
	require.NoError(t, err)

	proposalId, err = fresh.GetProposalID(ctx, chain, txhash)
	require.NoError(t, err)

	err = chain.PassProposal(ctx, proposalId)
	require.NoError(t, err)

	count = chain.QueryJSON(ctx, t, "data.count", "wasm", "contract-state", "smart", contractAddr, query).Int()
	require.Equal(t, int64(102), count)
}
