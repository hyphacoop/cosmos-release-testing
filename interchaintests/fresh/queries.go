package fresh

import (
	"context"
	"encoding/json"
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

func QuerySupply(ctx context.Context, chain Chain, denom string) (sdk.Coin, error) {
	stdout, _, err := chain.GetNode().ExecQuery(ctx, "bank", "total")
	if err != nil {
		return sdk.Coin{}, err
	}
	result := struct {
		Supply []sdk.Coin `json:"supply"`
	}{}
	if err := json.Unmarshal(stdout, &result); err != nil {
		return sdk.Coin{}, err
	}
	for _, supply := range result.Supply {
		if supply.Denom == denom {
			return supply, nil
		}
	}
	return sdk.Coin{}, fmt.Errorf("denom %s not found in supply", denom)
}
