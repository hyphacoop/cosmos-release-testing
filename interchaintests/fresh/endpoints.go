package fresh

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
)

func APIEndpointsTest(ctx context.Context, t *testing.T, chain Chain) {
	wallets, err := GetValidatorWallets(ctx, chain)
	require.NoError(t, err)
	const proposalID = "1"

	tests := []struct {
		name string
		path string
		key  string
	}{
		{name: "auth", path: "/cosmos/auth/v1beta1/accounts", key: "accounts"},
		{name: "bank", path: "/cosmos/bank/v1beta1/balances/" + wallets[0].Address, key: "balances"},
		{name: "bank_denoms_metadata", path: "/cosmos/bank/v1beta1/denoms_metadata", key: "metadatas"},
		{name: "supply", path: "/cosmos/bank/v1beta1/supply", key: "supply"},
		{name: "dist_slashes", path: "/cosmos/distribution/v1beta1/validators/" + wallets[0].ValoperAddress + "/slashes", key: "slashes"},
		{name: "evidence", path: "/cosmos/evidence/v1beta1/evidence", key: "evidence"},
		{name: "gov_proposals", path: "/cosmos/gov/v1beta1/proposals", key: "proposals"},
		{name: "gov_deposits", path: "/cosmos/gov/v1beta1/proposals/" + proposalID + "/deposits", key: "deposits"},
		{name: "gov_votes", path: "/cosmos/gov/v1beta1/proposals/" + proposalID + "/votes", key: "votes"},
		{name: "slash_signing_infos", path: "/cosmos/slashing/v1beta1/signing_infos", key: "info"},
		{name: "staking_delegations", path: "/cosmos/staking/v1beta1/delegations/" + wallets[0].Address, key: "delegation_responses"},
		{name: "staking_redelegations", path: "/cosmos/staking/v1beta1/delegators/" + wallets[0].Address + "/redelegations", key: "redelegation_responses"},
		{name: "staking_unbonding", path: "/cosmos/staking/v1beta1/delegators/" + wallets[0].Address + "/unbonding_delegations", key: "unbonding_responses"},
		{name: "staking_del_validators", path: "/cosmos/staking/v1beta1/delegators/" + wallets[0].Address + "/validators", key: "validators"},
		{name: "staking_validators", path: "/cosmos/staking/v1beta1/validators", key: "validators"},
		{name: "staking_val_delegations", path: "/cosmos/staking/v1beta1/validators/" + wallets[0].ValoperAddress + "/delegations", key: "delegation_responses"},
		{name: "staking_val_unbonding", path: "/cosmos/staking/v1beta1/validators/" + wallets[0].ValoperAddress + "/unbonding_delegations", key: "unbonding_responses"},
		{name: "tm_validatorsets", path: "/cosmos/base/tendermint/v1beta1/validatorsets/latest", key: "validators"},
	}

	for _, tt := range tests {
		t.Run("API "+tt.name, func(t *testing.T) {
			t.Parallel()
			endpoint := chain.GetHostAPIAddress() + tt.path
			resp, err := http.Get(endpoint)
			require.NoError(t, err)
			defer resp.Body.Close()
			require.Equal(t, http.StatusOK, resp.StatusCode)
			body := map[string]interface{}{}
			err = json.NewDecoder(resp.Body).Decode(&body)
			require.NoError(t, err)
			require.Contains(t, body, tt.key)
		})
	}
}

func RPCEndpointsTest(ctx context.Context, t *testing.T, chain Chain) {
	tests := []struct {
		name string
		path string
		key  string
	}{
		{name: "abci_info", path: "/abci_info", key: "response"},
		{name: "block", path: "/block", key: "block"},
		{name: "block_results", path: "/block_results", key: "begin_block_events"},
		{name: "blockchain", path: "/blockchain", key: "block_metas"},
		{name: "commit", path: "/commit", key: "signed_header"},
		{name: "consensus_params", path: "/consensus_params", key: "consensus_params"},
		{name: "consensus_state", path: "/consensus_state", key: "round_state"},
		{name: "dump_consensus_state", path: "/dump_consensus_state", key: "round_state"},
		{name: "genesis_chunked", path: "/genesis_chunked", key: "chunk"},
		{name: "net_info", path: "/net_info", key: "peers"},
		{name: "num_unconfirmed_txs", path: "/num_unconfirmed_txs", key: "n_txs"},
		{name: "unconfirmed_txs", path: "/unconfirmed_txs", key: "n_txs"},
		{name: "status", path: "/status", key: "node_info"},
		{name: "validators", path: "/validators", key: "validators"},
	}
	for _, tt := range tests {
		t.Run("RPC "+tt.name, func(t *testing.T) {
			t.Parallel()
			endpoint := chain.GetHostRPCAddress() + tt.path
			resp, err := http.Get(endpoint)
			require.NoError(t, err)
			defer resp.Body.Close()
			require.Equal(t, http.StatusOK, resp.StatusCode)
			body := map[string]interface{}{}
			err = json.NewDecoder(resp.Body).Decode(&body)
			require.NoError(t, err)
			require.Contains(t, body, "result")
			require.Contains(t, body["result"], tt.key)
		})
	}
}

func CheckEndpoint(ctx context.Context, t *testing.T, url string, f func([]byte) error) {
	resp, err := http.Get(url)
	require.NoError(t, err)
	defer resp.Body.Close()
	bts, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	require.NoError(t, f(bts))
}
