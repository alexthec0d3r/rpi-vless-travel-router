FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gawk file wget python3 zstd \
    libncurses-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ARG IB_URL="https://downloads.openwrt.org/snapshots/targets/bcm27xx/bcm2712/openwrt-imagebuilder-bcm27xx-bcm2712.Linux-x86_64.tar.zst"
WORKDIR /build

# Download and extract ImageBuilder (cached in Docker layer)
RUN wget -q --show-progress -O ib.tar.zst "${IB_URL}" && \
    tar --zstd -xf ib.tar.zst && \
    rm ib.tar.zst

# Copy build script and overlay files
COPY openwrt/build.sh /build/build.sh
COPY openwrt/files/ /build/files/
RUN chmod +x /build/build.sh

# Point build.sh at the pre-downloaded ImageBuilder
ENV IB_PATH="/build/openwrt-imagebuilder-bcm27xx-bcm2712.Linux-x86_64"
ENV OUTPUT_DIR="/output"

ENTRYPOINT ["/build/build.sh"]
