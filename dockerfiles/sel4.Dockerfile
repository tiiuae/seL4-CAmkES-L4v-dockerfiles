#
# Copyright 2020, Data61/CSIRO
#
# SPDX-License-Identifier: BSD-2-Clause
#

ARG BASE_IMG=base_tools
# hadolint ignore=DL3006
FROM $BASE_IMG
LABEL ORGANISATION="Trustworthy Systems"
LABEL MAINTAINER="Luke Mondy (luke.mondy@data61.csiro.au)"

# ARGS are env vars that are *only available* during the docker build
# They can be modified at docker build time via '--build-arg VAR="something"'
ARG SCM
ARG DESKTOP_MACHINE=no
ARG USE_DEBIAN_SNAPSHOT=yes
ARG MAKE_CACHES=yes
ARG DEFAULT_LOCALE='en_US.UTF-8 UTF-8'
ARG DEFAULT_LANG='en_US.UTF-8'
ARG DEFAULT_LANGUAGE='en_US:en:C'
ARG DEFAULT_KBLAYOUT='fi'

ARG SCRIPT=sel4.sh

COPY scripts /tmp/

RUN /bin/bash /tmp/${SCRIPT} \
    && apt-get clean autoclean \
    && apt-get autoremove --purge --yes \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=${DEFAULT_LANG}
ENV LANGUAGE=${DEFAULT_LANGUAGE}
