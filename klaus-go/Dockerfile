# OCI metadata is set via --annotation at build time.
ARG GO_VERSION=1.25
FROM golang:${GO_VERSION}-alpine AS go-source
FROM gsoci.azurecr.io/giantswarm/klaus:0.0.32
USER root
RUN apk add --no-cache git
COPY --from=go-source /usr/local/go /usr/local/go
RUN mkdir -p /go && chown klaus:klaus /go
USER klaus
ENV GOPATH=/go PATH="/usr/local/go/bin:/go/bin:${PATH}"
