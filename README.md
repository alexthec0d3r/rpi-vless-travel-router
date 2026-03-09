# RPi VLESS Travel Router

**Turn a Raspberry Pi 5 into a pocket-sized VPN router that encrypts all your traffic.**

Plug it into any hotel/cafe/airport ethernet, connect your devices to its WiFi hotspot, and everything goes through your VLESS+Reality VPN tunnel — invisible to DPI, unblockable by firewalls.

No apps to install. No manual proxy configs. Just connect to WiFi and go.

## What You Get

- **Encrypted WiFi hotspot** — connect any device (phone, laptop, tablet, smart TV)
- **VLESS + Reality protocol** — the gold standard for bypassing censorship and DPI
- **Zero-config VPN** — all traffic transparently proxied via TPROXY, no client apps needed
- **LuCI web interface** — manage everything from your browser at `http://192.168.4.1`
- **PassWall GUI** — add/edit/test VPN servers with a visual interface
- **Auto-failover** — optional backup server with automatic switching
- **Russian service bypass** — optional direct routing for Russian domains (for users in Russia)
- **Portable** — powered by USB-C, fits in your pocket

## Requirements

- **Raspberry Pi 5** (4GB or 8GB)
- **MicroSD card** (8GB+ recommended)
- **Ethernet cable** (for upstream internet)
- **A VLESS+Reality VPN server** (you can use any existing one, or [set up your own](docs/SERVER-SETUP.md))
- **Docker** (for building the image)

## Quick Start

### 1. Clone & configure

```bash
git clone https://github.com/alexthec0d3r/rpi-vless-travel-router.git
cd rpi-vless-travel-router

cp config.env.example config.env
# Edit config.env with your VPN server details, WiFi name, and passwords
```

### 2. Generate overlay files

```bash
chmod +x configure.sh
./configure.sh
```

### 3. Build the image

```bash
chmod +x docker-build.sh
./docker-build.sh
```

This builds a Docker container with the OpenWrt ImageBuilder, compiles the firmware, and drops the `.img.gz` into `output/`.

First build downloads ~1GB (ImageBuilder + packages). Subsequent builds use Docker cache.

### 4. Flash to SD card

```bash
gunzip -k output/openwrt-*.img.gz

# macOS
sudo dd if=output/openwrt-*.img of=/dev/rdiskN bs=4m status=progress

# Linux
sudo dd if=output/openwrt-*.img of=/dev/sdX bs=4M status=progress
```

### 5. Boot & connect

1. Insert SD card into RPi5
2. Connect ethernet to upstream network
3. Power on via USB-C
4. Wait ~30 seconds for boot
5. Connect to WiFi (SSID and password from your `config.env`)
6. All your traffic is now encrypted through your VPN!

## Management

- **Web UI**: `http://192.168.4.1` (LuCI)
- **VPN settings**: Services → PassWall (in LuCI)
- **SSH**: `ssh root@192.168.4.1`

## Configuration Options

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WIFI_SSID` | Yes | `TravelRouter` | WiFi network name |
| `WIFI_PASSWORD` | Yes | `changeme123` | WiFi password |
| `ROOT_PASSWORD` | Yes | `changeme123` | SSH/LuCI password |
| `VPN_SERVER_ADDRESS` | Yes | — | VPN server IP or hostname |
| `VPN_SERVER_PORT` | Yes | `443` | VPN server port |
| `VPN_UUID` | Yes | — | VLESS UUID |
| `VPN_REALITY_PUBLIC_KEY` | Yes | — | Reality public key |
| `VPN_REALITY_SHORT_ID` | Yes | — | Reality short ID |
| `VPN_REALITY_SNI` | Yes | — | SNI domain |
| `VPN_TRANSPORT` | No | `tcp` | `tcp` (Vision) or `xhttp` |
| `VPN_BACKUP_ENABLED` | No | `false` | Enable backup server |
| `RUSSIAN_BYPASS` | No | `none` | `geosite` for Russian bypass |

See `config.env.example` for full details including backup server options.

## Architecture

```
┌─────────────────────────────────────┐
│  Your Devices (Phone, Laptop, ...)  │
│         Connect to WiFi             │
└─────────────┬───────────────────────┘
              │ WiFi (TravelRouter)
              ▼
┌─────────────────────────────────────┐
│         Raspberry Pi 5              │
│         ┌───────────────┐           │
│         │   OpenWrt     │           │
│         │   + PassWall  │           │
│         │   + TPROXY    │           │
│         └───────┬───────┘           │
│                 │ All traffic       │
│                 ▼ transparently     │
│         ┌───────────────┐           │
│         │  xray-core    │           │
│         │  VLESS+Reality│           │
│         └───────┬───────┘           │
└─────────────────┼───────────────────┘
                  │ Encrypted tunnel
                  │ (looks like normal HTTPS)
                  ▼
          ┌───────────────┐
          │  Your VPN     │
          │  Server       │
          │  ─────────►   │──► Internet
          └───────────────┘
```

For more details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Troubleshooting

**WiFi not appearing?**
- Wait 30-60 seconds after boot — the radio takes time to initialize
- Check if the green LED on RPi5 is solid (booted) vs blinking (still booting)

**Can't reach 192.168.4.1?**
- Make sure you're connected to the travel router's WiFi, not your regular network
- Try `http://192.168.4.1` (not https)

**VPN not working?**
- Open LuCI → Services → PassWall → check node status
- Verify your VPN server is running and reachable
- Check PassWall logs in LuCI for connection errors

**Build fails?**
- Make sure Docker is running and has ~4GB free disk space
- Run `./docker-build.sh --no-cache` for a clean rebuild
- Check that `./configure.sh` completed without errors

## Docs

- [Server Setup Guide](docs/SERVER-SETUP.md) — How to set up your own VLESS+Reality server
- [Architecture](docs/ARCHITECTURE.md) — Technical overview of how it all works
- [PassWall Tips](docs/PASSWALL-TIPS.md) — Using the PassWall LuCI interface

## License

GPL-2.0 — see [LICENSE](LICENSE).

## Credits

Built with [OpenWrt](https://openwrt.org/), [xray-core](https://github.com/XTLS/Xray-core), and [PassWall](https://github.com/xiaorouji/openwrt-passwall).
