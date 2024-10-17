# SPDX-License-Identifier: Apache-2.0

FROM quay.io/projectquay/golang:1.22 AS builder

WORKDIR /kubesan

COPY go.mod go.sum ./
RUN go mod download

COPY api/ api/
COPY cmd/ cmd/
COPY internal/ internal/

RUN go build -o bin/kubesan cmd/main.go

# CentOS Stream 9 doesn't provide package nbd
# FROM quay.io/centos/centos:stream9
FROM quay.io/fedora/fedora:40

# util-linux-core, e2fsprogs, and xfsprogs are for Filesystem volume support where
# blkid(8) and mkfs are required by k8s.io/mount-utils.
RUN dnf install -qy nbd qemu-img util-linux-core e2fsprogs xfsprogs && dnf clean all

WORKDIR /kubesan

COPY --from=builder /kubesan/bin/kubesan bin/

ENTRYPOINT [ "/kubesan/bin/kubesan" ]