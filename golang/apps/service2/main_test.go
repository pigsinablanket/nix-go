package main

import "testing"

func TestGreet(t *testing.T) {
	msg, err := greet()
	if err != nil {
		t.Fatalf("greet() returned unexpected error: %v", err)
	}
	want := "Powered by pkg/errors"
	if msg != want {
		t.Errorf("greet() = %q, want %q", msg, want)
	}
}
