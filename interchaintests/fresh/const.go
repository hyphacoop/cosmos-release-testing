package fresh

const (
	UPGRADE_DELTA   = int64(10)
	DENOM           = "uatom"
	NUM_VALIDATORS  = 3
	VALIDATOR_FUNDS = 11_000_000_000
	// This moniker is hardcoded into the chain's genesis process.
	VALIDATOR_MONIKER = "validator"
)

func getValidatorStake() [NUM_VALIDATORS]int64 {
	return [NUM_VALIDATORS]int64{80_000_000, 12_000_000, 8_000_000}
}
