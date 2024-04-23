package stateful_test

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/strangelove-ventures/interchaintest/v7"
	"github.com/strangelove-ventures/interchaintest/v7/chain/cosmos"
	"github.com/strangelove-ventures/interchaintest/v7/ibc"
	"github.com/strangelove-ventures/interchaintest/v7/testutil"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
)

const (
	SnapRPC  = "https://rpc.cosmos.nodestake.org:443"
	AddrBook = "https://ss.cosmos.nodestake.org/addrbook.json"
	Seed     = "7954d10a367f1a9556530a40680ab1df6b14d4a4@rpc.cosmos.nodestake.org:666"
)

func getFromURL(t *testing.T, url string, path string) gjson.Result {
	rsp, err := http.Get(url)
	require.NoError(t, err)
	defer rsp.Body.Close()
	bts, err := io.ReadAll(rsp.Body)
	require.NoError(t, err)
	return gjson.GetBytes(bts, path)
}

func configToml(t *testing.T, latestBlockHeight, blockHeightHash string) testutil.Toml {
	toml := make(testutil.Toml)
	statesync := make(testutil.Toml)
	blockHeightInt, err := strconv.Atoi(latestBlockHeight)
	require.NoError(t, err)
	statesync["trust_height"] = blockHeightInt
	statesync["trust_hash"] = blockHeightHash
	statesync["rpc_servers"] = fmt.Sprintf("%s,https://cosmos-rpc.polkachu.com:443", SnapRPC)
	statesync["enable"] = true
	statesync["chunk_request_timeout"] = "180s"

	p2p := make(testutil.Toml)
	p2p["seeds"] = Seed

	toml["statesync"] = statesync
	toml["p2p"] = p2p
	return toml
}

func appToml(t *testing.T) testutil.Toml {
	toml := make(testutil.Toml)
	api := make(testutil.Toml)
	api["rpc-read-timeout"] = 180
	toml["api"] = api
	return toml
}

func TestLaunchChain(t *testing.T) {
	ctx := context.Background()
	latestBlockHeight := getFromURL(t, SnapRPC+"/block", "result.block.header.height").String()
	require.NotEmpty(t, latestBlockHeight)
	blockHeightHash := getFromURL(t, SnapRPC+"/block?height="+latestBlockHeight, "result.block_id.hash").String()
	require.NotEmpty(t, blockHeightHash)

	config := configToml(t, latestBlockHeight, blockHeightHash)
	chains := interchaintest.CreateChainWithConfig(t, 1, 0, "gaia", "v15.2.0", ibc.ChainConfig{
		ConfigFileOverrides: map[string]any{
			"config/config.toml": config,
			"config/app.toml":    appToml(t),
		},
		ChainID:   "cosmoshub-4",
		SkipGenTx: true,
	})
	gaia := chains[0].(*cosmos.CosmosChain)

	dockerClient, dockerNetwork := interchaintest.DockerSetup(t)
	err := gaia.Initialize(ctx, t.Name(), dockerClient, dockerNetwork)
	require.NoError(t, err)

	rsp, err := http.Get(AddrBook)
	require.NoError(t, err)
	defer rsp.Body.Close()
	bts, err := io.ReadAll(rsp.Body)
	require.NoError(t, err)

	err = gaia.GetNode().WriteFile(ctx, bts, "config/addrbook.json")
	require.NoError(t, err)

	gaia.Start(t.Name(), ctx)
	// require.Error(t, err)

	time.Sleep(20 * time.Minute)
	// err = testutil.WaitForInSync(ctx, gaia, gaia.GetNode())
	err = testutil.WaitForBlocks(ctx, 10, gaia)
	require.NoError(t, err)
}
