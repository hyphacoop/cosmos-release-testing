package fresh

import (
	"fmt"
	"time"
)

const (
	UPGRADE_DELTA        = int64(30)
	DENOM                = "uatom"
	NUM_VALIDATORS       = 6
	NUM_FULL_NODES       = 0
	VALIDATOR_FUNDS      = 11_000_000_000
	VALIDATOR_STAKE_STEP = 1_000_000
	// This moniker is hardcoded into the chain's genesis process.
	VALIDATOR_MONIKER        = "validator"
	CONSUMER_DENOM           = "ucon"
	STRIDE_DENOM             = "ustrd"
	NEUTRON_DENOM            = "untrn"
	TRANSFER_PORT_ID         = "transfer"
	PROVIDER_PORT_ID         = "provider"
	CONSUMER_PORT_ID         = "consumer"
	SLASHING_WINDOW_PROVIDER = 10
	SLASHING_WINDOW_CONSUMER = 20
	DEFAULT_CHANNEL_VERSION  = "ics20-1"
	PSS_DISABLED             = -1
	PSS_OPT_IN               = 0
	GOV_MIN_DEPOSIT_AMOUNT   = 1000
	GOV_DEPOSIT_AMOUNT       = "5000000" + DENOM
	// These durations are a little finniky, don't toy with them too much.
	COMMIT_TIMEOUT          = 4 * time.Second
	GOV_DEPOSIT_PERIOD      = 60 * time.Second
	GOV_VOTING_PERIOD       = 80 * time.Second
	CHAIN_SPAWN_WAIT        = 155 * time.Second
	DOWNTIME_JAIL_DURATION  = 10 * time.Second
	BLOCKS_PER_DISTRIBUTION = 10
)

func getValidatorStake() [NUM_VALIDATORS]int64 {
	return [NUM_VALIDATORS]int64{
		30_000_000,
		29_000_000,
		20_000_000,
		10_000_000,
		7_000_000,
		4_000_000,
	}
}

func NoProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{false, false, false, false, false, false}
}

func SomeProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{true, false, false, true, false, false}
}

func AllProviderKeysCopied() [NUM_VALIDATORS]bool {
	return [NUM_VALIDATORS]bool{true, true, true, true, true, true}
}

func RelayerTransferPathFor(chainA, chainB Chain) string {
	return fmt.Sprintf("tx-%s-%s", chainA.Config().ChainID, chainB.Config().ChainID)
}

func RelayerICSPathFor(chainA, chainB Chain) string {
	return fmt.Sprintf("ics-%s-%s", chainA.Config().ChainID, chainB.Config().ChainID)
}
