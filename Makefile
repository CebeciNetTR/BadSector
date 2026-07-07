.PHONY: dev build test lint docker-up docker-down test-env smoke-test

dev-api:
	cd api && go run ./cmd/badsector-api

dev-ui:
	cd ui && npm run dev

build:
	cd api && go build -o ../bin/badsector-api ./cmd/badsector-api
	cd worker && go build -o ../bin/badsector-worker ./cmd/badsector-worker
	cd cli && go build -o ../bin/badsector ./cmd/badsector
	cd ui && npm run build

test:
	go test ./...

test-env:
	./scripts/setup-dev-data.sh
	docker compose up -d --build

smoke-test:
	chmod +x scripts/smoke-test.sh && ./scripts/smoke-test.sh

docker-up: test-env

docker-down:
	docker compose down

lint:
	go vet ./...