package main

import (
	"fmt"

	example "github.com/example/pkg"
)

func main() {
	fmt.Println("Hello from service1")
	fmt.Println(example.Greeting())
}
