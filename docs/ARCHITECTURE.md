# Architecture

## Overview

The travel router runs OpenWrt on a Raspberry Pi 5, using PassWall + xray-core to create a transparent VPN proxy for all connected devices.

## Network Topology

```
Internet ← Ethernet (eth0/WAN) ← RPi5 ← WiFi AP (br-lan/LAN) ← Your Devices
```

- **WAN** (`eth0`): Connects to upstream network via DHCP (hotel ethernet, tethered phone, etc.)
- **LAN** (`br-lan`): WiFi access point on `192.168.4.0/24`
- **DHCP**: dnsmasq serves `192.168.4.10–100` to WiFi clients

## Transparent Proxy (TPROXY)

PassWall uses TPROXY (transparent proxy) to intercept all TCP/UDP traffic from LAN clients without any client-side configuration:

1. LAN client sends packet to any IP (e.g., `8.8.8.8:443`)
2. nftables TPROXY rule intercepts in the PREROUTING chain
3. Packet is redirected to xray's local dokodemo-door listener
4. xray wraps it in VLESS+Reality and sends to your VPN server
5. VPN server unwraps and forwards to the real destination
6. Response travels back the same path

No DNS leaks — PassWall's DNS mode uses xray to resolve via the remote server.

## PassWall

[PassWall](https://github.com/xiaorouji/openwrt-passwall) is the LuCI (OpenWrt web UI) app that manages everything:

- **Node management**: Add/edit/test/delete VPN servers via web GUI
- **Auto-switch**: If primary node goes down, automatically tries backup nodes
- **Routing rules**: geosite/geoip based split routing
- **TPROXY setup**: Manages nftables rules and policy routing automatically
- **DNS**: Handles DNS through xray to prevent leaks

## Split Routing (Optional)

When `RUSSIAN_BYPASS=geosite` is set:
- Russian domains (`geosite:category-ru`) → direct (bypass VPN)
- Russian IPs (`geoip:ru`) → direct
- Everything else → through VPN

This is for users in Russia who need to bypass censorship for international sites while keeping Russian services fast.

## WiFi

The CYW43455 chip on RPi5 provides 2.4GHz WiFi (802.11n). It's configured as an access point with WPA2 (PSK2) encryption. The 2.4GHz band is used for maximum device compatibility.

## Boot Sequence

1. OpenWrt boots from SD card
2. `99-travel-router` runs once (first boot):
   - Enables PassWall service
   - Configures WiFi AP (SSID, password)
   - Sets root password
   - Sets up geo data symlinks
3. PassWall starts xray-core with configured nodes
4. nftables TPROXY rules are applied
5. Router is ready — WiFi AP appears
