FROM golang:1.19-alpine AS busybox-min

RUN apk add --update --no-cache wget curl make git libc-dev bash gcc linux-headers eudev-dev

# Build minimal busybox
WORKDIR /
# busybox v1.34.1 stable
RUN git clone -b 1_34_1 --single-branch https://git.busybox.net/busybox
WORKDIR /busybox
ADD busybox.min.config .config
RUN make

FROM boxboat/config-merge:latest as config-merge

FROM golang:1.19-alpine

RUN apk add wget curl lz4 nano jq npm

# Install busybox
COPY --from=busybox-min /busybox/busybox /busybox/busybox

# Add config-merge
COPY --from=config-merge /usr/local/config-merge /usr/local/config-merge
COPY --from=config-merge /usr/local/bin/config-merge /usr/local/bin/config-merge
COPY --from=config-merge /usr/local/bin/envsubst /usr/local/bin/envsubst

# Add dasel
RUN if [ "$(uname -m)" = "aarch64" ]; then \
      ARCH=arm64; \
    else \
      ARCH=amd64; \
    fi; \
    wget -O /usr/local/bin/dasel https://github.com/TomWright/dasel/releases/download/v1.26.0/dasel_linux_$ARCH
RUN chmod +x /usr/local/bin/dasel
