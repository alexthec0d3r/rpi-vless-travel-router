#!/bin/bash
set -euo pipefail

#
# OpenWrt Image Builder for Travel Router (Raspberry Pi 5)
# Target: bcm27xx/bcm2712 SNAPSHOT
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${IB_PATH:-${SCRIPT_DIR}/_build}"
FILES_DIR="${SCRIPT_DIR}/files"
OUTPUT_DIR="${OUTPUT_DIR:-}"

# OpenWrt ImageBuilder settings
TARGET="bcm27xx"
SUBTARGET="bcm2712"
IB_URL="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${SUBTARGET}/openwrt-imagebuilder-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst"
IB_ARCHIVE="$(basename "${IB_URL}")"
IB_DIR="openwrt-imagebuilder-${TARGET}-${SUBTARGET}.Linux-x86_64"

# PassWall feed
PASSWALL_FEED_URL="https://github.com/xiaorouji/openwrt-passwall-packages.git;main"
PASSWALL_LUCI_FEED_URL="https://github.com/xiaorouji/openwrt-passwall.git;main"

# Image profile for RPi5
PROFILE="rpi-5"

# Packages to install
PACKAGES=(
    # LuCI web UI
    luci
    luci-ssl

    # PassWall (LuCI VPN management GUI)
    luci-app-passwall

    # Xray core (used by PassWall)
    xray-core

    # Geo data for routing rules (geosite:category-ru, geoip:ru, etc.)
    v2ray-geoip
    v2ray-geosite

    # WiFi AP (remove default wpad-basic-mbedtls to avoid conflict)
    -wpad-basic-mbedtls
    hostapd-openssl
    kmod-brcmfmac

    # DNS
    -dnsmasq
    dnsmasq-full

    # Firewall / nftables
    nftables
    kmod-nft-tproxy
    kmod-nf-tproxy

    # Networking utilities
    ip-full

    # CLI tools
    curl
    wget
    jq

    # SSH file transfer
    openssh-sftp-server

    # Optional: web terminal
    luci-app-ttyd

    # Block device / partition support
    block-mount
    kmod-fs-ext4
    e2fsprogs
)

# --------------------------------------------------------------------------- #
#  Functions
# --------------------------------------------------------------------------- #

log() {
    echo ">>> $*"
}

ensure_deps() {
    local missing=()
    for cmd in wget tar zstd make gawk getopt file python3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} )); then
        echo "ERROR: Missing build dependencies: ${missing[*]}"
        echo "Install them first. On Debian/Ubuntu:"
        echo "  sudo apt install build-essential libncurses-dev zstd gawk getopt file wget python3"
        exit 1
    fi
}

check_generated_files() {
    local ok=true
    if [[ ! -f "${FILES_DIR}/etc/config/passwall" ]]; then
        echo "ERROR: PassWall config not found at ${FILES_DIR}/etc/config/passwall"
        ok=false
    fi
    if [[ ! -f "${FILES_DIR}/etc/uci-defaults/99-travel-router" ]]; then
        echo "ERROR: First-boot script not found at ${FILES_DIR}/etc/uci-defaults/99-travel-router"
        ok=false
    fi
    if [[ "$ok" != "true" ]]; then
        echo ""
        echo "Run ./configure.sh first to generate overlay files from config.env"
        exit 1
    fi
}

download_imagebuilder() {
    # If IB_PATH is set and points to an existing ImageBuilder, skip download
    if [[ -n "${IB_PATH:-}" && -f "${IB_PATH}/Makefile" ]]; then
        log "Using pre-existing ImageBuilder at ${IB_PATH}"
        BUILD_DIR="${IB_PATH}"
        IB_DIR="."
        return
    fi

    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    if [[ -d "${IB_DIR}" ]]; then
        log "ImageBuilder already extracted at ${BUILD_DIR}/${IB_DIR}"
        return
    fi

    if [[ ! -f "${IB_ARCHIVE}" ]]; then
        log "Downloading OpenWrt ImageBuilder..."
        wget --progress=bar:force:noscroll -O "${IB_ARCHIVE}" "${IB_URL}"
    fi

    log "Extracting ImageBuilder..."
    tar --zstd -xf "${IB_ARCHIVE}"
    log "ImageBuilder ready."
}

add_passwall_feeds() {
    local ib_path
    if [[ "${IB_DIR}" == "." ]]; then
        ib_path="${BUILD_DIR}"
    else
        ib_path="${BUILD_DIR}/${IB_DIR}"
    fi
    local repos_conf="${ib_path}/repositories.conf"

    log "Configuring PassWall package feeds..."

    if grep -q "passwall" "${repos_conf}" 2>/dev/null; then
        log "PassWall feeds already configured."
        return
    fi

    cat >> "${repos_conf}" <<'FEEDS'

## PassWall proxy packages
src/gz passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages/releases/latest/download
src/gz passwall_luci https://github.com/xiaorouji/openwrt-passwall/releases/latest/download
FEEDS

    sed -i 's/^option check_signature$/# option check_signature/' "${repos_conf}" 2>/dev/null || true

    log "PassWall feeds added to repositories.conf"
}

copy_custom_files() {
    log "Preparing custom files overlay..."

    if [[ ! -d "${FILES_DIR}" ]]; then
        log "WARNING: No files/ directory found at ${FILES_DIR}"
        return
    fi

    find "${FILES_DIR}" -path "*/init.d/*" -exec chmod 755 {} \;
    find "${FILES_DIR}" -path "*/uci-defaults/*" -exec chmod 755 {} \;

    log "Custom files ready at ${FILES_DIR}"
}

build_image() {
    local ib_path
    if [[ "${IB_DIR}" == "." ]]; then
        ib_path="${BUILD_DIR}"
    else
        ib_path="${BUILD_DIR}/${IB_DIR}"
    fi
    cd "${ib_path}"

    local pkg_list
    pkg_list="$(IFS=' '; echo "${PACKAGES[*]}")"

    log "Building OpenWrt image..."
    log "  Profile: ${PROFILE}"
    log "  Packages: ${pkg_list}"
    log "  Files: ${FILES_DIR}"
    log ""

    make image \
        PROFILE="${PROFILE}" \
        PACKAGES="${pkg_list}" \
        FILES="${FILES_DIR}" \
        ROOTFS_PARTSIZE=512 \
        CONFIG_TARGET_ROOTFS_PARTSIZE=512 \
        2>&1 | tee "${SCRIPT_DIR}/build.log"

    log ""
    log "Build complete!"
    log ""

    # Find and report the output image
    local output_dir="${ib_path}/bin/targets/${TARGET}/${SUBTARGET}"
    if [[ -d "${output_dir}" ]]; then
        log "Output images:"
        ls -lh "${output_dir}"/*.img.gz 2>/dev/null || log "No .img.gz files found"

        # Copy to OUTPUT_DIR if set
        if [[ -n "${OUTPUT_DIR}" ]]; then
            mkdir -p "${OUTPUT_DIR}"
            cp "${output_dir}"/*.img.gz "${OUTPUT_DIR}/" 2>/dev/null || true
            log ""
            log "Images copied to ${OUTPUT_DIR}/"
            ls -lh "${OUTPUT_DIR}"/*.img.gz 2>/dev/null || true
        fi

        log ""
        log "Flash with:"
        log "  gunzip -k *.img.gz && sudo dd if=*.img of=/dev/sdX bs=4M status=progress"
    else
        log "WARNING: Output directory not found at ${output_dir}"
        log "Check build.log for errors."
    fi
}

# --------------------------------------------------------------------------- #
#  Main
# --------------------------------------------------------------------------- #

main() {
    log "=========================================="
    log " Travel Router - OpenWrt Image Builder"
    log " Target: RPi5 (${TARGET}/${SUBTARGET})"
    log "=========================================="
    echo ""

    ensure_deps
    check_generated_files
    download_imagebuilder
    add_passwall_feeds
    copy_custom_files
    build_image

    log ""
    log "Done."
}

main "$@"
