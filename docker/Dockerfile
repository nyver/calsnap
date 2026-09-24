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

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/calsnap-server /calsnap-server
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/calsnap-server"]
CMD ["-config", "/etc/calsnap/config.yaml"]
