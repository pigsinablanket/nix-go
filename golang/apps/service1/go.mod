module github.com/example/service1

go 1.23

require github.com/example/pkg v0.0.0

require github.com/go-chi/chi/v5 v5.3.2

replace github.com/example/pkg => ../../pkg/example
