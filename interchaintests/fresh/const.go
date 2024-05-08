package fresh

import (
	"fmt"
	"time"
)

const (
	UPGRADE_DELTA        = int64(10)
	DENOM                = "uatom"
	NUM_VALIDATORS       = 3
	VALIDATOR_FUNDS      = 11_000_000_000
	VALIDATOR_STAKE_STEP = 1_000_000
	// This moniker is hardcoded into the chain's genesis process.
	VALIDATOR_MONIKER        = "validator"
	GOV_DEPOSIT_AMOUNT       = "5000000" + DENOM
	CONSUMER_DENOM           = "ucon"
	STRIDE_DENOM             = "ustrd"
	NEUTRON_DENOM            = "untrn"
	TRANSFER_PORT_ID         = "transfer"
	PROVIDER_PORT_ID         = "provider"
	CONSUMER_PORT_ID         = "consumer"
	COMMIT_TIMEOUT           = 5 * time.Second
	SLASHING_WINDOW_PROVIDER = 10
	SLASHING_WINDOW_CONSUMER = 20
	DOWNTIME_JAIL_DURATION   = 10 * time.Second
	DEFAULT_CHANNEL_VERSION  = "ics20-1"
	PSS_DISABLED             = -1
	PSS_OPT_IN               = 0
)

func getValidatorStake() [NUM_VALIDATORS]int64 {
	return [NUM_VALIDATORS]int64{80_000_000, 12_000_000, 8_000_000}
}

func NoProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{false, false, false}
}

func SomeProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{true, false, false}
}

func AllProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{true, true, true}
}

func RelayerTransferPathFor(chainA, chainB Chain) string {
	return fmt.Sprintf("tx-%s-%s", chainA.Config().ChainID, chainB.Config().ChainID)
}

func RelayerICSPathFor(chainA, chainB Chain) string {
	return fmt.Sprintf("ics-%s-%s", chainA.Config().ChainID, chainB.Config().ChainID)
}
