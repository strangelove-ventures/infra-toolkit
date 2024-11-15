FROM alpine:3 AS build-env
RUN apk add --update --no-cache \
  automake \
  autoconf \
  bash \
  bison \
  curl \
  eudev-dev \
  flex \
  gcc \
  git \
  libc-dev \
  libtool \
  linux-headers \
  make \
  vim \
  wget
ARG TARGETARCH
ARG BUILDARCH
RUN LIBDIR=/lib; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
      ARCH=aarch64; \
      if [ "${BUILDARCH}" != "arm64" ]; then \
        wget -c https://musl.cc/aarch64-linux-musl-cross.tgz -O - | tar -xzvv --strip-components 1 -C /usr; \
        LIBDIR=/usr/aarch64-linux-musl/lib; \
        mkdir -p $LIBDIR; \
      fi; \
    elif [ "${TARGETARCH}" = "amd64" ]; then \
      ARCH=x86_64; \
      if [ "${BUILDARCH}" != "amd64" ]; then \
        wget -c https://musl.cc/x86_64-linux-musl-cross.tgz -O - | tar -xzvv --strip-components 1 -C /usr; \
        LIBDIR=/usr/x86_64-linux-musl/lib; \
        mkdir -p $LIBDIR; \
      fi; \
    fi;
# Build minimal busybox
WORKDIR /
RUN git clone -b 1_34_1 --single-branch https://git.busybox.net/busybox
WORKDIR /busybox
COPY busybox.min.config .config
RUN if [ "${TARGETARCH}" = "arm64" ] && [ "${BUILDARCH}" != "arm64" ]; then \
      export CC=aarch64-linux-musl-gcc; \
    elif [ "${TARGETARCH}" = "amd64" ] && [ "${BUILDARCH}" != "amd64" ]; then \
      export CC=x86_64-linux-musl-gcc; \
    fi; \
    make
# Static jq
WORKDIR /
RUN git clone --recursive -b jq-1.6 --single-branch https://github.com/stedolan/jq.git
WORKDIR /jq
RUN autoreconf -fi;\
  ./configure --with-oniguruma=builtin;\ 
  make LDFLAGS=-all-static

FROM boxboat/config-merge:0.2.1 as config-merge

FROM alpine:3
RUN apk add --no-cache \
  curl \
  lz4 \
  nano \
  npm \
  rsync \
  tar \
  wget \
  zstd-dev \
  python3 \
  py3-pip \
  tmux \
  vim \
  python3-dev \
  sudo

# Create operator user and group, and set up sudo
RUN addgroup -g 1000 operator && \
    adduser -D -u 1000 -G operator operator && \
    echo "operator ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/operator && \
    chmod 0440 /etc/sudoers.d/operator

# Install gcloud
RUN apk add --no-cache python3 curl bash && \
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-453.0.0-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-453.0.0-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --quiet --path-update=true --usage-reporting=false --additional-components beta gsutil && \
    rm -f google-cloud-cli-453.0.0-linux-x86_64.tar.gz && \
    ln -s /google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud && \
    ln -s /google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil && \
    chown -R operator:operator /google-cloud-sdk

# Create and activate a virtual environment
RUN python3 -m venv /opt/venv && \
    chown -R operator:operator /opt/venv && \
    chmod -R 755 /opt/venv/bin  # Ensure executables are runnable

ENV PATH="/opt/venv/bin:/google-cloud-sdk/bin:$PATH"

# Install gsutil and fix permissions
USER operator
RUN /opt/venv/bin/pip3 install --upgrade pip && \
    /opt/venv/bin/pip3 install gsutil google-cloud-storage

# Make sure all files in venv are owned by operator
USER root
RUN chown -R operator:operator /opt/venv && \
    chmod -R 755 /opt/venv/bin

# Switch back to operator for the remaining operations
USER operator

# Install busybox
COPY --from=build-env /busybox/busybox /busybox/busybox

# Install jq
COPY --from=build-env /jq/jq /usr/local/bin/jq

# Add config-merge
COPY --from=config-merge /usr/local/config-merge /usr/local/config-merge
COPY --from=config-merge /usr/local/bin/config-merge /usr/local/bin/config-merge
COPY --from=config-merge /usr/local/bin/envsubst /usr/local/bin/envsubst

# Switch to root for dasel installation
USER root

# Add dasel
RUN if [ "$(uname -m)" = "aarch64" ]; then \
      ARCH=arm64 DASELSUM="8e1f95b5f361f68ed8376d5a9593ae4249e28153a05b26f1f99f9466efeac5c9  /usr/local/bin/dasel"; \
    else \
      ARCH=amd64 DASELSUM="3efd202a525c43c027bddc770861dd637ec8389a4ca3ef2951da7165350219ed  /usr/local/bin/dasel"; \
    fi; \
    wget -O /usr/local/bin/dasel https://github.com/TomWright/dasel/releases/download/v1.26.0/dasel_linux_$ARCH && \
      sha256sum -c <(echo "$DASELSUM") && \
      chmod +x /usr/local/bin/dasel

# Set ownership of working directory and home directory
RUN mkdir -p /app && chown operator:operator /app && \
    mkdir -p /home/operator && chown -R operator:operator /home/operator

# Switch to operator user at the end
USER operator
WORKDIR /app
ENTRYPOINT ["/bin/sh"]
