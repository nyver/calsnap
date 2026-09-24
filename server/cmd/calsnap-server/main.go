// Command calsnap-server is the stateless CalSnap backend: it accepts a meal
// photo, asks a configurable AI vision provider to recognize the foods and
// returns them with nutrition per 100 g. It stores nothing.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/config"
	"example.com/calsnap/server/internal/metrics"
	"example.com/calsnap/server/internal/nutrition"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/transport/httpapi"
	"example.com/calsnap/server/internal/vision/fake"
	"example.com/calsnap/server/internal/vision/gemini"
	"example.com/calsnap/server/internal/vision/openai"
)

// version is set at build time: -ldflags "-X main.version=1.2.3".
var version = "dev"

const (
	exitOK     = 0
	exitFailed = 1
	exitUsage  = 2

	limiterSweepInterval = time.Minute
	limiterIdleTTL       = 10 * time.Minute
	maxHeaderBytes       = 16 << 10
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, os.Getenv))
}

func run(args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fs := flag.NewFlagSet("calsnap-server", flag.ContinueOnError)
	fs.SetOutput(stderr)
	configPath := fs.String("config", "", "path to the YAML configuration file (defaults are used when empty)")
	showVersion := fs.Bool("version", false, "print the version and exit")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *showVersion {
		fmt.Fprintln(stdout, "calsnap-server", version)
		return exitOK
	}

	cfg, err := config.Load(*configPath, getenv)
	if err != nil {
		fmt.Fprintf(stderr, "configuration error: %v\n", err)
		return exitUsage
	}
	log := newLogger(cfg.Log, stderr)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	rt, err := build(cfg, log)
	if err != nil {
		log.Error("startup failed", "error", err.Error())
		return exitFailed
	}
	apiLn, err := (&net.ListenConfig{}).Listen(ctx, "tcp", cfg.Server.Listen)
	if err != nil {
		log.Error("listen failed", "address", cfg.Server.Listen, "error", err.Error())
		return exitFailed
	}
	metricsLn, err := (&net.ListenConfig{}).Listen(ctx, "tcp", cfg.Metrics.Listen)
	if err != nil {
		log.Error("metrics listen failed", "address", cfg.Metrics.Listen, "error", err.Error())
		_ = apiLn.Close()
		return exitFailed
	}

	if !cfg.Server.TLS.Enabled() {
		log.Warn("serving plain HTTP: TLS must be terminated by a trusted reverse proxy",
			"environment", cfg.Server.Environment)
	}
	log.Info("calsnap-server starting", "version", version, "listen", apiLn.Addr().String(),
		"metrics", metricsLn.Addr().String(), "environment", cfg.Server.Environment, "ai_provider", cfg.AI.Provider)

	if err := rt.serve(ctx, apiLn, metricsLn); err != nil {
		log.Error("server stopped with an error", "error", err.Error())
		return exitFailed
	}
	log.Info("calsnap-server stopped")
	return exitOK
}

func newLogger(cfg config.LogConfig, w io.Writer) *slog.Logger {
	level, _ := config.ParseLevel(cfg.Level) // validated by config.Load
	opts := &slog.HandlerOptions{Level: level}
	if cfg.Format == "text" {
		return slog.New(slog.NewTextHandler(w, opts))
	}
	return slog.New(slog.NewJSONHandler(w, opts))
}

// app holds the wired servers and their shutdown policy.
type app struct {
	log             *slog.Logger
	api             *http.Server
	metrics         *http.Server
	limiter         *ratelimit.Limiter
	certFile        string
	keyFile         string
	shutdownTimeout time.Duration
}

// build wires the composition root.
func build(cfg *config.Config, log *slog.Logger) (*app, error) {
	catalog, err := nutrition.LoadEmbedded(cfg.Nutrition.FuzzyThreshold)
	if err != nil {
		return nil, fmt.Errorf("load nutrition catalog: %w", err)
	}
	log.Info("nutrition catalog loaded", "version", catalog.Version(), "foods", catalog.Len())

	var vision analysis.FoodVisionProvider
	switch cfg.AI.Provider {
	case config.ProviderGemini:
		vision = gemini.New(gemini.Config{
			BaseURL: cfg.AI.Gemini.BaseURL,
			Model:   cfg.AI.Gemini.Model,
			APIKey:  cfg.AI.Gemini.APIKey,
		}, &http.Client{Timeout: cfg.AI.CallTimeout})
	case config.ProviderOpenRouter:
		vision = openai.New(openai.Config{
			BaseURL: cfg.AI.OpenRouter.BaseURL,
			Model:   cfg.AI.OpenRouter.Model,
			APIKey:  cfg.AI.OpenRouter.APIKey,
		}, &http.Client{Timeout: cfg.AI.CallTimeout})
	case config.ProviderRouterAI:
		vision = openai.New(openai.Config{
			BaseURL: cfg.AI.RouterAI.BaseURL,
			Model:   cfg.AI.RouterAI.Model,
			APIKey:  cfg.AI.RouterAI.APIKey,
		}, &http.Client{Timeout: cfg.AI.CallTimeout})
	case config.ProviderFake:
		log.Warn("using the fake AI provider: canned results, for development only")
		vision = fake.Provider{}
	default:
		return nil, fmt.Errorf("unsupported ai.provider %q", cfg.AI.Provider)
	}

	prefixes, err := cfg.TrustedProxyPrefixes()
	if err != nil {
		return nil, err
	}
	m := metrics.New()
	svc := analysis.NewService(analysis.Config{
		ProviderName:     cfg.AI.Provider,
		MinConfidence:    cfg.AI.MinConfidence,
		CallTimeout:      cfg.AI.CallTimeout,
		OverallTimeout:   cfg.AI.OverallTimeout,
		MaxConcurrent:    cfg.Limits.MaxConcurrentAnalyses,
		QueueWait:        cfg.Limits.QueueWait,
		ReplayTTL:        cfg.Limits.ReplayTTL,
		ReplayMaxEntries: cfg.Limits.ReplayMaxEntries,
	}, analysis.Deps{Vision: vision, Nutrition: catalog, Metrics: m, Logger: log})

	limiter := ratelimit.New(ratelimit.Config{
		PerMinute:  cfg.Limits.RatePerMinute,
		Burst:      cfg.Limits.RateBurst,
		MaxClients: cfg.Limits.MaxTrackedClients,
		IdleTTL:    limiterIdleTTL,
	})

	handler := httpapi.NewHandler(httpapi.Deps{
		Analyzer:            svc,
		Limiter:             limiter,
		TrustedProxies:      prefixes,
		Observer:            m,
		Logger:              log,
		MaxUploadBytes:      cfg.Limits.MaxUploadBytes,
		MaxImageDimensionPx: cfg.Limits.MaxImageDimensionPx,
		ClientConfig: httpapi.ClientConfig{
			ImageMaxLongSidePx:    cfg.Client.ImageMaxLongSidePx,
			ImageJPEGQuality:      cfg.Client.ImageJPEGQuality,
			MaxUploadBytes:        cfg.Limits.MaxUploadBytes,
			AnalyzeTimeoutSeconds: cfg.Client.AnalyzeTimeoutSeconds,
		},
	})

	api := &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: cfg.Server.ReadHeaderTime,
		ReadTimeout:       cfg.Server.ReadTimeout,
		WriteTimeout:      cfg.Server.WriteTimeout,
		IdleTimeout:       cfg.Server.IdleTimeout,
		MaxHeaderBytes:    maxHeaderBytes,
	}
	if cfg.Server.TLS.Enabled() {
		api.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", m.Handler())
	metricsSrv := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: cfg.Server.ReadHeaderTime,
		ReadTimeout:       cfg.Server.ReadTimeout,
		WriteTimeout:      cfg.Server.ReadTimeout,
		IdleTimeout:       cfg.Server.IdleTimeout,
	}

	return &app{
		log:             log,
		api:             api,
		metrics:         metricsSrv,
		limiter:         limiter,
		certFile:        cfg.Server.TLS.CertFile,
		keyFile:         cfg.Server.TLS.KeyFile,
		shutdownTimeout: cfg.Server.ShutdownTimeout,
	}, nil
}

// serve runs both listeners and the rate limiter janitor until ctx is
// cancelled (SIGINT/SIGTERM) or a listener fails. It then stops accepting new
// connections and waits up to the shutdown timeout for in-flight requests.
func (a *app) serve(ctx context.Context, apiLn, metricsLn net.Listener) error {
	const servers = 2
	done := make(chan error, servers)
	go func() {
		var err error
		if a.api.TLSConfig != nil {
			err = a.api.ServeTLS(apiLn, a.certFile, a.keyFile)
		} else {
			err = a.api.Serve(apiLn)
		}
		done <- ignoreClosed(err)
	}()
	go func() { done <- ignoreClosed(a.metrics.Serve(metricsLn)) }()

	janitorCtx, stopJanitor := context.WithCancel(ctx)
	janitorDone := make(chan struct{})
	go func() {
		defer close(janitorDone)
		a.limiter.Run(janitorCtx, limiterSweepInterval)
	}()

	var firstErr error
	pending := servers
	select {
	case <-ctx.Done():
		a.log.Info("shutdown requested, waiting for in-flight requests", "timeout", a.shutdownTimeout.String())
	case firstErr = <-done:
		pending--
	}

	// ctx is already cancelled, but shutdown needs its own deadline.
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), a.shutdownTimeout)
	defer cancel()
	if err := a.api.Shutdown(shutdownCtx); err != nil {
		firstErr = errors.Join(firstErr, fmt.Errorf("shut down API server: %w", err))
		_ = a.api.Close()
	}
	if err := a.metrics.Shutdown(shutdownCtx); err != nil {
		firstErr = errors.Join(firstErr, fmt.Errorf("shut down metrics server: %w", err))
		_ = a.metrics.Close()
	}
	stopJanitor()
	<-janitorDone

	// Collect the results of the serve goroutines (they return once Shutdown ran).
	for ; pending > 0; pending-- {
		if err := <-done; err != nil {
			firstErr = errors.Join(firstErr, err)
		}
	}
	return firstErr
}

func ignoreClosed(err error) error {
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
