ARG BUILDPLATFORM=linux/amd64
FROM --platform=${BUILDPLATFORM} node:lts-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git &&\
    MCSM_VERSION=$(git ls-remote --tags --sort=-v:refname https://github.com/MCSManager/MCSManager.git | grep -oP 'v\d+\.\d+\.\d+$' | head -1) &&\
    echo "Building MCSManager version: ${MCSM_VERSION}" &&\
    git clone --depth 1 --branch "${MCSM_VERSION}" https://github.com/MCSManager/MCSManager.git . &&\
    rm -rf .git

RUN chmod a+x ./install-dependents.sh &&\
    chmod a+x ./build.sh &&\
    ./install-dependents.sh &&\
    ./build.sh

FROM ghcr.io/linuxserver/baseimage-alpine:edge

RUN apk add --no-cache \
    nodejs \
    npm

COPY --from=builder /src/production-code/web/ /opt/mcsmanager/web/

COPY web /

EXPOSE 23333

VOLUME ["/opt/mcsmanager/web/data", "/opt/mcsmanager/web/logs"]
