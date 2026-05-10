# syntax=docker/dockerfile:1

FROM golang:1.25-alpine AS builder

WORKDIR /src
RUN apk add --no-cache ca-certificates git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/envpilot ./apps/api

FROM alpine:3.21

RUN apk add --no-cache ca-certificates git openssh-client tzdata && \
    addgroup -S -g 10001 envpilot && \
    adduser -S -D -H -u 10001 -G envpilot -h /var/lib/envpilot envpilot && \
    mkdir -p /var/lib/envpilot && \
    chown -R envpilot:envpilot /var/lib/envpilot

USER 10001:10001
WORKDIR /var/lib/envpilot

COPY --from=builder /out/envpilot /usr/local/bin/envpilot
COPY --from=builder /src/migrations/postgres /var/lib/envpilot/migrations/postgres

ENV ENVPILOT_ADDR=:8080 \
    ENVPILOT_DATA_DIR=/var/lib/envpilot \
    ENVPILOT_GITOPS_DIR=/var/lib/envpilot/gitops

EXPOSE 8080
ENTRYPOINT ["envpilot"]
