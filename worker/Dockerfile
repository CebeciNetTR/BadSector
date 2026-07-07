FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates gcc musl-dev

WORKDIR /src
COPY go.mod go.sum* ./
COPY api/ ./api/
COPY worker/ ./worker/
RUN go mod tidy
RUN CGO_ENABLED=1 go build -trimpath -ldflags="-s -w" -o /badsector-worker ./worker/cmd/badsector-worker
FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /badsector-worker /usr/local/bin/badsector-worker
ENV BADSECTOR_RUNTIME=/runtime
ENTRYPOINT ["badsector-worker"]
