package main

import (
	"fmt"

	"github.com/pkg/errors"
)

func main() {
	fmt.Println("Hello from service2")
	msg, err := greet()
	if err != nil {
		fmt.Println(errors.Wrap(err, "greeting failed"))
		return
	}
	fmt.Println(msg)
}

func greet() (string, error) {
	return "Powered by pkg/errors", nil
}
