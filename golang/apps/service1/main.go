package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	example "github.com/example/pkg"
)

const defaultPort = "8080"

var greetingFlag = flag.String("greeting", "", "greeting to return (default: built-in)")

type greetingResponse struct {
	Service   string `json:"service"`
	Greeting  string `json:"greeting"`
	RequestID string `json:"request_id"`
}

func main() {
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: newRouter(),
	}

	go func() {
		slog.Info("service1 listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
}

func newRouter() *chi.Mux {
	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.Recoverer)

	r.Get("/healthz", handleHealthz)
	r.Get("/api/v1/greeting", handleGreeting)
	return r
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleGreeting(w http.ResponseWriter, r *http.Request) {
	greeting := example.Greeting()
	if *greetingFlag != "" {
		greeting = *greetingFlag
	}
	writeJSON(w, http.StatusOK, greetingResponse{
		Service:   "service1",
		Greeting:  greeting,
		RequestID: chimw.GetReqID(r.Context()),
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
