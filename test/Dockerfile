# Rime test bench: try a Rime schema without touching the host input method.
#
# librime-bin has rime_deployer but no interactive console, so rime_test.c
# (a small console on the librime C API) is built here. Same librime 1.10
# as Ubuntu 24.04's fcitx5-rime, so behaviour should match the host.
#
# The Rime user data folder (schema, dict sources, compiled tables and the
# learned user dictionary) is mounted at /rime; see run.sh.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        librime1t64 \
        librime-bin \
        librime-data \
        librime-plugin-lua \
        librime-dev \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY rime_test.c /tmp/rime_test.c
RUN gcc -O2 -Wall -o /usr/local/bin/rime_test /tmp/rime_test.c -lrime \
    && rm /tmp/rime_test.c

WORKDIR /rime
VOLUME ["/rime"]

ENTRYPOINT ["rime_test"]
