# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG TOOLCHAIN_DEB
COPY .deps/${TOOLCHAIN_DEB} /tmp/${TOOLCHAIN_DEB}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends make python3 /tmp/${TOOLCHAIN_DEB} \
    && rm -rf /var/lib/apt/lists/* /tmp/${TOOLCHAIN_DEB}

WORKDIR /workspace
CMD ["/bin/bash"]
