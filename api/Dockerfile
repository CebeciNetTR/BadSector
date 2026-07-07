FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates gcc musl-dev

WORKDIR /src
COPY go.mod go.sum* ./
COPY api/ ./api/
RUN go mod tidy
RUN CGO_ENABLED=1 go build -trimpath -ldflags="-s -w" -o /badsector-api ./api/cmd/badsector-api
FROM alpine:3.19
RUN apk add --no-cache ca-certificates wget

COPY --from=builder /badsector-api /usr/local/bin/badsector-api

ENV BADSECTOR_API_ADDR=:8080
ENV BADSECTOR_RUNTIME=/etc/badsector/runtime
ENV BADSECTOR_DATABASE_URL=sqlite:///data/badsector.db

EXPOSE 8080
VOLUME ["/data", "/etc/badsector/runtime"]

HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1

ENTRYPOINT ["badsector-api"]
