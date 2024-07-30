package fresh

import (
	"strings"
	"testing"

	sdkmath "cosmossdk.io/math"
	"github.com/stretchr/testify/require"
)

func StrToSDKInt(t *testing.T, s string) sdkmath.Int {
	t.Helper()
	s, _, _ = strings.Cut(s, ".")
	i, ok := sdkmath.NewIntFromString(s)
	require.Truef(t, ok, "s: %s", s)
	return i
}

func checkAMinusBEqualsX(t *testing.T, a, b string, x sdkmath.Int) {
	t.Helper()
	intA := StrToSDKInt(t, a)
	intB := StrToSDKInt(t, b)
	require.True(t, intA.Sub(intB).Equal(x), "a - b = %s, expected %s", intA.Sub(intB).String(), x.String())
}
