# syntax=docker/dockerfile:1
#
# Build from the repository root:
#   docker build -f docker/Dockerfile -t calsnap-server --build-arg VERSION=1.0.0 .

FROM golang:1.26 AS build
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
ARG VERSION=dev
# Static binary without CGO so that it runs in a distroless image.
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
    -o /out/calsnap-server ./cmd/calsnap-server

# A writable, non-root-owned directory for the self-signed certificate. A named
# volume mounted here inherits the ownership (distroless has no shell to chown).
RUN mkdir -p /out/state

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/calsnap-server /calsnap-server
COPY --from=build --chown=65532:65532 /out/state /var/lib/calsnap
# Relative paths from the config (the default server.tls.self_signed_dir "certs")
# resolve to the writable volume instead of the read-only root file system.
WORKDIR /var/lib/calsnap
USER nonroot:nonroot
EXPOSE 8445
ENTRYPOINT ["/calsnap-server"]
CMD ["-config", "/etc/calsnap/config.yaml"]
