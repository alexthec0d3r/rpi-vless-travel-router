# PassWall Tips

## Accessing PassWall

1. Connect to the travel router's WiFi
2. Open `http://192.168.4.1` in your browser
3. Log in with your root password
4. Navigate to **Services → PassWall**

## Checking VPN Status

The PassWall main page shows:
- **Node status**: Green = connected, Red = disconnected
- **Current node**: Which server is active
- **Traffic stats**: Bytes sent/received

## Adding a New Server

1. Go to **Services → PassWall → Node List**
2. Click **Add**
3. Fill in:
   - **Type**: Xray
   - **Protocol**: VLESS
   - **Address**: Your server IP
   - **Port**: Server port
   - **UUID**: Your VLESS UUID
   - **Flow**: `xtls-rprx-vision` (for TCP/Vision)
   - **TLS**: Enable
   - **Reality**: Enable
   - Fill in Reality public key, short ID, server name
4. Click **Save & Apply**

## Testing a Node

1. Go to **Node List**
2. Click the **Test** button next to a node
3. PassWall will test connectivity and show latency

## Auto-Switch Setup

If you have multiple servers:
1. Go to **Services → PassWall → Auto Switch**
2. Enable auto-switch
3. Add your nodes in priority order
4. Set testing interval (default: 30 seconds)
5. If the active node fails health checks, PassWall switches to the next one

## Viewing Logs

- **PassWall logs**: Services → PassWall → Log
- **System logs**: Status → System Log
- **SSH**: `logread | grep passwall`

## Changing Proxy Mode

- **Global**: All traffic through VPN (default)
- **GFW List**: Only blocked sites through VPN (Russian bypass mode)
- **Direct**: No VPN (bypass mode for debugging)

Change in: Services → PassWall → Basic Settings → TCP Proxy Mode

## Updating Geo Data

PassWall uses `geosite.dat` and `geoip.dat` for routing rules. To update:

1. SSH into the router
2. Run:
   ```bash
   wget -O /usr/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
   wget -O /usr/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
   /etc/init.d/passwall restart
   ```
