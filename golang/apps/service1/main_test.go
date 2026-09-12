package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	example "github.com/example/pkg"
)

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	newRouter().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decoding body: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("status = %q, want %q", body["status"], "ok")
	}
}

func TestGreeting(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/greeting", nil)
	rec := httptest.NewRecorder()
	newRouter().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	var body greetingResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decoding body: %v", err)
	}
	if body.Service != "service1" {
		t.Errorf("service = %q, want %q", body.Service, "service1")
	}
	if want := example.Greeting(); body.Greeting != want {
		t.Errorf("greeting = %q, want %q", body.Greeting, want)
	}
	if body.RequestID == "" {
		t.Error("request_id = empty, want non-empty")
	}
}
