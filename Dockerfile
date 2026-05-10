# syntax=docker/dockerfile:1

FROM golang:1.25-alpine AS builder

WORKDIR /src
RUN apk add --no-cache ca-certificates

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/envpilot-install ./cmd/envpilot-install

FROM alpine:3.21

RUN apk add --no-cache ca-certificates helm kubectl tzdata && \
    addgroup -S -g 10001 envpilot && \
    adduser -S -D -H -u 10001 -G envpilot -h /var/lib/envpilot envpilot && \
    mkdir -p /var/lib/envpilot /opt/envpilot/helm && \
    chown -R envpilot:envpilot /var/lib/envpilot /opt/envpilot

COPY --from=builder /out/envpilot-install /usr/local/bin/envpilot-install
COPY deploy/helm /opt/envpilot/helm

USER 10001:10001
WORKDIR /var/lib/envpilot

ENTRYPOINT ["envpilot-install"]
