ARG BUILDPLATFORM=linux/amd64
ARG EMBEDDED_JAVA_VERSION=none

FROM --platform=${BUILDPLATFORM} node:lts-alpine AS builder

WORKDIR /src
ARG MCSM_VERSION
RUN apk add --no-cache git &&\
    MCSM_VERSION=${MCSM_VERSION:-$(git ls-remote --tags --sort=-v:refname https://github.com/MCSManager/MCSManager.git | grep -oP 'v\d+\.\d+\.\d+$' | head -1)} &&\
    echo "Building MCSManager version: ${MCSM_VERSION}" &&\
    git clone --depth 1 --branch "${MCSM_VERSION}" https://github.com/MCSManager/MCSManager.git . &&\
    rm -rf .git

RUN apk add --no-cache wget &&\
    chmod a+x ./install-dependents.sh &&\
    chmod a+x ./build.sh &&\
    ./install-dependents.sh &&\
    ./build.sh &&\
    wget --input-file=lib-urls.txt --directory-prefix=production-code/daemon/lib/ &&\
    chmod a+x production-code/daemon/lib/*

FROM ghcr.io/linuxserver/baseimage-debian:trixie

ARG EMBEDDED_JAVA_VERSION

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && apt-get install -y -no-install-recommends curl &&\
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash &&\
    apt-get update && apt-get install -y -no-install-recommends nodejs &&\
    if [ "${EMBEDDED_JAVA_VERSION}" != "none" ] && [ -n "${EMBEDDED_JAVA_VERSION}" ]; then \
      apt-get install -y --no-install-recommends wget apt-transport-https gpg &&\
      wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null &&\
      echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list &&\
      mkdir -p /usr/share/man/man1 &&\
      apt-get update && apt-get install -no-install-recommends -y "temurin-${EMBEDDED_JAVA_VERSION}-jre"; \
    fi &&\
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/production-code/daemon/ /opt/mcsmanager/daemon/

COPY daemon /

EXPOSE 24444

ENV MCSM_INSTANCES_BASE_PATH=/opt/mcsmanager/daemon/data/InstanceData

VOLUME ["/opt/mcsmanager/daemon/data", "/opt/mcsmanager/daemon/logs"]
