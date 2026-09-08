package example

import "testing"

func TestGreeting(t *testing.T) {
	got := Greeting()
	want := "Hello from example package"
	if got != want {
		t.Errorf("Greeting() = %q, want %q", got, want)
	}
}
