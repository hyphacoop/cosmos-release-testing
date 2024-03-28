package fresh

import (
	"context"
	"os"
	"path"
	"testing"

	"github.com/kelseyhightower/envconfig"
	"github.com/strangelove-ventures/interchaintest/v7/testreporter"
	"go.uber.org/zap"
	"go.uber.org/zap/zaptest"
)

type testReporterKey struct{}

type relayerExecReporterKey struct{}

type loggerKey struct{}

type configKey struct{}

type Config struct {
	StartVersion     string `envconfig:"START_VERSION" default:"v15.1.0"`
	UpgradeVersion   string `envconfig:"UPGRADE_VERSION" default:"main"`
	TargetVersion    string `envconfig:"TARGET_VERSION" default:"v16"`
	DockerRepository string `envconfig:"DOCKER_REPOSITORY" default:"gaia"`
}

func WithTestReporter(ctx context.Context, r *testreporter.Reporter) context.Context {
	return context.WithValue(ctx, testReporterKey{}, r)
}

func GetTestReporter(ctx context.Context) *testreporter.Reporter {
	r, _ := ctx.Value(testReporterKey{}).(*testreporter.Reporter)
	return r
}

func WithRelayerExecReporter(ctx context.Context, r *testreporter.RelayerExecReporter) context.Context {
	return context.WithValue(ctx, relayerExecReporterKey{}, r)
}

func GetRelayerExecReporter(ctx context.Context) *testreporter.RelayerExecReporter {
	r, _ := ctx.Value(relayerExecReporterKey{}).(*testreporter.RelayerExecReporter)
	return r
}

func WithLogger(ctx context.Context, l *zap.Logger) context.Context {
	return context.WithValue(ctx, loggerKey{}, l)
}

func GetLogger(ctx context.Context) *zap.Logger {
	l, _ := ctx.Value(loggerKey{}).(*zap.Logger)
	return l
}

func WithConfig(ctx context.Context, c *Config) context.Context {
	return context.WithValue(ctx, configKey{}, c)
}

func GetConfig(ctx context.Context) *Config {
	c, _ := ctx.Value(configKey{}).(*Config)
	return c
}

func setEnvironment() error {
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	if err := os.Setenv("IBCTEST_CONFIGURED_CHAINS", path.Join(cwd, "..", "configuredChains.yaml")); err != nil {
		return err
	}
	if err := os.Setenv("CONTAINER_LOG_TAIL", "250"); err != nil {
		return err
	}
	return nil
}

func NewTestContext(t *testing.T) (context.Context, error) {
	ctx := context.Background()
	logger := zaptest.NewLogger(t)
	ctx = WithLogger(ctx, logger)

	testReporter := testreporter.NewReporter(os.Stderr)
	ctx = WithTestReporter(ctx, testReporter)
	relayerExecReporter := testReporter.RelayerExecReporter(t)
	ctx = WithRelayerExecReporter(ctx, relayerExecReporter)

	config := &Config{}
	err := envconfig.Process("TEST", config)
	if err != nil {
		return nil, err
	}
	ctx = WithConfig(ctx, config)

	// This isn't exactly a concern of the test context, but it's a convenient place to set this. Every test calls this function.
	if err := setEnvironment(); err != nil {
		return nil, err
	}

	return ctx, nil
}
