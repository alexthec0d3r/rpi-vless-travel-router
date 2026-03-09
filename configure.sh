#!/bin/bash
set -euo pipefail

#
# configure.sh — Generate overlay files from config.env + templates
# Run this BEFORE building the image.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
PASSWALL_OUT="${SCRIPT_DIR}/openwrt/files/etc/config/passwall"
FIRSTBOOT_OUT="${SCRIPT_DIR}/openwrt/files/etc/uci-defaults/99-travel-router"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}>>>${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

# ── Load config ──────────────────────────────────────────────────────────────
if [[ ! -f "${CONFIG_FILE}" ]]; then
    error "config.env not found. Copy the example and fill it in:
  cp config.env.example config.env"
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# ── Validate required fields ─────────────────────────────────────────────────
missing=()
for var in WIFI_SSID WIFI_PASSWORD ROOT_PASSWORD \
           VPN_SERVER_ADDRESS VPN_SERVER_PORT VPN_UUID \
           VPN_REALITY_PUBLIC_KEY VPN_REALITY_SHORT_ID VPN_REALITY_SNI; do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done

if (( ${#missing[@]} )); then
    error "Missing required config values: ${missing[*]}
  Edit config.env and fill in all required fields."
fi

# Validate transport
VPN_TRANSPORT="${VPN_TRANSPORT:-tcp}"
if [[ "$VPN_TRANSPORT" != "tcp" && "$VPN_TRANSPORT" != "xhttp" ]]; then
    error "VPN_TRANSPORT must be 'tcp' or 'xhttp' (got: ${VPN_TRANSPORT})"
fi

if [[ "$VPN_TRANSPORT" == "xhttp" && -z "${VPN_XHTTP_PATH:-}" ]]; then
    error "VPN_XHTTP_PATH is required when VPN_TRANSPORT=xhttp"
fi

RUSSIAN_BYPASS="${RUSSIAN_BYPASS:-none}"
VPN_BACKUP_ENABLED="${VPN_BACKUP_ENABLED:-false}"

# ── Build primary node transport/flow fields ─────────────────────────────────
if [[ "$VPN_TRANSPORT" == "xhttp" ]]; then
    PRIMARY_FLOW=""
    PRIMARY_TRANSPORT="	option transport 'xhttp'\n	option xhttp_path '${VPN_XHTTP_PATH}'"
    PRIMARY_REMARKS="VLESS XHTTP ${VPN_SERVER_PORT}"
else
    PRIMARY_FLOW="xtls-rprx-vision"
    PRIMARY_TRANSPORT=""
    PRIMARY_REMARKS="VLESS Vision ${VPN_SERVER_PORT}"
fi

# ── Build proxy mode (global or geosite bypass) ─────────────────────────────
if [[ "$RUSSIAN_BYPASS" == "geosite" ]]; then
    PROXY_MODE="gfwlist"
else
    PROXY_MODE="global"
fi

# ── Build backup node section ────────────────────────────────────────────────
BACKUP_NODE=""
AUTOSWITCH_ENABLE="0"
AUTOSWITCH_SECTION=""

if [[ "$VPN_BACKUP_ENABLED" == "true" ]]; then
    # Validate backup fields
    for var in VPN_BACKUP_ADDRESS VPN_BACKUP_PORT VPN_BACKUP_UUID \
               VPN_BACKUP_REALITY_PUBLIC_KEY VPN_BACKUP_REALITY_SHORT_ID VPN_BACKUP_REALITY_SNI; do
        if [[ -z "${!var:-}" ]]; then
            error "VPN_BACKUP_ENABLED=true but ${var} is empty"
        fi
    done

    VPN_BACKUP_TRANSPORT="${VPN_BACKUP_TRANSPORT:-tcp}"
    if [[ "$VPN_BACKUP_TRANSPORT" == "xhttp" ]]; then
        BACKUP_FLOW=""
        BACKUP_TRANSPORT_LINE="	option transport 'xhttp'\n	option xhttp_path '${VPN_BACKUP_XHTTP_PATH:-}'"
        BACKUP_REMARKS="VLESS XHTTP ${VPN_BACKUP_PORT}"
    else
        BACKUP_FLOW="xtls-rprx-vision"
        BACKUP_TRANSPORT_LINE=""
        BACKUP_REMARKS="VLESS Vision ${VPN_BACKUP_PORT}"
    fi

    BACKUP_NODE="# Backup server
config nodes 'node_backup'
	option remarks 'Backup - ${BACKUP_REMARKS}'
	option type 'Xray'
	option protocol 'vless'
	option address '${VPN_BACKUP_ADDRESS}'
	option port '${VPN_BACKUP_PORT}'
	option uuid '${VPN_BACKUP_UUID}'
	option flow '${BACKUP_FLOW}'
$(echo -e "${BACKUP_TRANSPORT_LINE}")
	option tls '1'
	option reality '1'
	option reality_publicKey '${VPN_BACKUP_REALITY_PUBLIC_KEY}'
	option reality_shortId '${VPN_BACKUP_REALITY_SHORT_ID}'
	option reality_serverName '${VPN_BACKUP_REALITY_SNI}'
	option reality_fingerprint 'chrome'
	option tls_serverName '${VPN_BACKUP_REALITY_SNI}'
	option fingerprint 'chrome'"

    AUTOSWITCH_ENABLE="1"
    AUTOSWITCH_SECTION="config auto_switch
	option enable '1'
	option testing_time '30'
	option connect_timeout '3'
	option retry_num '3'
	option restore_switch '1'
	list tcp_node 'node_primary'
	list tcp_node 'node_backup'"
fi

# ── Generate PassWall config ─────────────────────────────────────────────────
log "Generating PassWall config..."

mkdir -p "$(dirname "${PASSWALL_OUT}")"

sed_passwall() {
    sed \
        -e "s|@@PROXY_MODE@@|${PROXY_MODE}|g" \
        -e "s|@@AUTOSWITCH_ENABLE@@|${AUTOSWITCH_ENABLE}|g" \
        -e "s|@@VPN_SERVER_ADDRESS@@|${VPN_SERVER_ADDRESS}|g" \
        -e "s|@@VPN_SERVER_PORT@@|${VPN_SERVER_PORT}|g" \
        -e "s|@@VPN_UUID@@|${VPN_UUID}|g" \
        -e "s|@@VPN_PRIMARY_FLOW@@|${PRIMARY_FLOW}|g" \
        -e "s|@@VPN_PRIMARY_REMARKS@@|${PRIMARY_REMARKS}|g" \
        -e "s|@@VPN_REALITY_PUBLIC_KEY@@|${VPN_REALITY_PUBLIC_KEY}|g" \
        -e "s|@@VPN_REALITY_SHORT_ID@@|${VPN_REALITY_SHORT_ID}|g" \
        -e "s|@@VPN_REALITY_SNI@@|${VPN_REALITY_SNI}|g" \
        "${TEMPLATES_DIR}/passwall.tpl"
}

# Generate base config with simple sed replacements
sed_passwall > "${PASSWALL_OUT}.tmp"

# Handle multi-line block replacements using temp files (compatible with macOS/BSD)
_tmp_transport="$(mktemp)"
_tmp_backup="$(mktemp)"
_tmp_autoswitch="$(mktemp)"
echo -e "${PRIMARY_TRANSPORT}" > "$_tmp_transport"
printf '%s\n' "${BACKUP_NODE}" > "$_tmp_backup"
printf '%s\n' "${AUTOSWITCH_SECTION}" > "$_tmp_autoswitch"

# Process line by line, replacing placeholder lines with block content
while IFS= read -r line; do
    case "$line" in
        *@@VPN_PRIMARY_TRANSPORT@@*)
            [[ -n "${PRIMARY_TRANSPORT}" ]] && cat "$_tmp_transport"
            ;;
        *@@BACKUP_NODE@@*)
            [[ -n "${BACKUP_NODE}" ]] && cat "$_tmp_backup"
            ;;
        *@@AUTOSWITCH_SECTION@@*)
            [[ -n "${AUTOSWITCH_SECTION}" ]] && cat "$_tmp_autoswitch"
            ;;
        *)
            printf '%s\n' "$line"
            ;;
    esac
done < "${PASSWALL_OUT}.tmp" > "${PASSWALL_OUT}"

rm -f "${PASSWALL_OUT}.tmp" "$_tmp_transport" "$_tmp_backup" "$_tmp_autoswitch"

log "  -> ${PASSWALL_OUT}"

# ── Generate first-boot script ───────────────────────────────────────────────
log "Generating first-boot script..."

mkdir -p "$(dirname "${FIRSTBOOT_OUT}")"

sed \
    -e "s|@@WIFI_SSID@@|${WIFI_SSID}|g" \
    -e "s|@@WIFI_PASSWORD@@|${WIFI_PASSWORD}|g" \
    -e "s|@@ROOT_PASSWORD@@|${ROOT_PASSWORD}|g" \
    "${TEMPLATES_DIR}/99-travel-router.tpl" > "${FIRSTBOOT_OUT}"

chmod 755 "${FIRSTBOOT_OUT}"

log "  -> ${FIRSTBOOT_OUT}"

# ── Verify no leftover placeholders ──────────────────────────────────────────
for file in "${PASSWALL_OUT}" "${FIRSTBOOT_OUT}"; do
    if grep -q '@@' "$file"; then
        warn "WARNING: Leftover @@placeholders@@ in $file:"
        grep '@@' "$file"
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Configuration Complete!                ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC} WiFi SSID:       ${GREEN}${WIFI_SSID}${NC}"
echo -e "${CYAN}║${NC} VPN Server:      ${GREEN}${VPN_SERVER_ADDRESS}:${VPN_SERVER_PORT}${NC}"
echo -e "${CYAN}║${NC} Transport:       ${GREEN}${VPN_TRANSPORT}${NC}"
if [[ "$VPN_BACKUP_ENABLED" == "true" ]]; then
echo -e "${CYAN}║${NC} Backup Server:   ${GREEN}${VPN_BACKUP_ADDRESS}:${VPN_BACKUP_PORT}${NC}"
fi
echo -e "${CYAN}║${NC} Russian Bypass:  ${GREEN}${RUSSIAN_BYPASS}${NC}"
echo -e "${CYAN}║${NC} Proxy Mode:      ${GREEN}${PROXY_MODE}${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC} Next step: ${YELLOW}./docker-build.sh${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
