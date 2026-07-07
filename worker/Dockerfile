FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum* ./
COPY api/internal/ ./api/internal/
COPY worker/ ./worker/
RUN go mod download
RUN go build -o /badsector-worker ./worker/cmd/badsector-worker

FROM alpine:3.19
COPY --from=builder /badsector-worker /usr/local/bin/badsector-worker
ENV BADSECTOR_RUNTIME=/runtime
ENTRYPOINT ["badsector-worker"]
