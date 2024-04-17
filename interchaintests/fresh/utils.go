package fresh

import (
	"strings"
	"testing"

	sdkmath "cosmossdk.io/math"
	"github.com/stretchr/testify/require"
)

func strToSDKInt(t *testing.T, s string) sdkmath.Int {
	t.Helper()
	s, _, _ = strings.Cut(s, ".")
	i, ok := sdkmath.NewIntFromString(s)
	require.Truef(t, ok, "s: %s", s)
	return i
}

func checkAMinusBEqualsX(t *testing.T, a, b string, x int64) {
	t.Helper()
	// trim the .00s from the string
	intA := strToSDKInt(t, a)
	intB := strToSDKInt(t, b)
	require.Equal(t, x, intA.Sub(intB).Int64())
}
