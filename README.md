# RouteRus

<div align="center">

![RouteRus](https://img.shields.io/badge/RouteRus-3X--UI%20Pro-blue?style=for-the-badge)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg?style=flat-square)](https://github.com/anfixit/routerus/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange.svg?style=flat-square&logo=ubuntu)](https://ubuntu.com/)

**Automated 3X-UI Pro installer with VLESS+REALITY, smart routing, and ad blocking**

[Installation](#installation) | [Features](#features) | [Documentation](#documentation) | [Credits](#credits)

</div>

---

## What is RouteRus?

RouteRus is a fully automated deployment script for the 3X-UI panel with:
- VLESS + REALITY protocol (full traffic masking)
- All services on port 443 (panel + connections)
- Ad and tracker blocking
- Split-routing for Russian domains
- Automatic SSL via Let's Encrypt
- Telegram bot fix (correct VLESS links)

## Features

### Security
- **REALITY masking** — VPN traffic looks like regular HTTPS
- **Fake website** — additional camouflage layer
- **UFW firewall** — only ports 22, 80, 443 open
- **Nginx reverse proxy** — panel protection
- **Random paths** — obscured panel access

### Smart routing

**Blocked** (optional):
- Ads: Google Analytics, Yandex Metrika, Facebook Pixel
- QUIC/HTTP3: UDP 443 for non-Russian IPs
- Vulnerable ports: UDP 135, 137, 138, 139

**Direct** (bypasses VPN, optional):
- Russian domains: .ru, .su, .рф
- Russian services: Yandex, VK, Steam, Sberbank
- Russian IPs (GeoIP)
- Local networks
- BitTorrent traffic

**Through VPN**:
- Everything else

## Installation

### Requirements
- Ubuntu 24.04 (clean install)
- Root access
- 2 domains (free via [DuckDNS](https://www.duckdns.org))

### Getting domains

1. Register at [DuckDNS.org](https://www.duckdns.org)
2. Create 2 subdomains:
   ```
   mypanel.duckdns.org    -> your server IP
   myreality.duckdns.org  -> your server IP
   ```
3. Wait 1-2 minutes for DNS propagation

### One-line install

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh)"
```

### Interactive mode

The script will prompt:
```
Enter panel subdomain: mypanel.duckdns.org
Enter REALITY subdomain: myreality.duckdns.org
Enable ad blocking? (y/n) [default: y]: y
Enable RU routing? (y/n) [default: y]: y
Block QUIC? (y/n) [default: y]: y
```

### Automated mode

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh) \
  --subdomain mypanel.duckdns.org \
  --reality-domain myreality.duckdns.org \
  --enable-adblock y \
  --enable-ru-routing y \
  --enable-quic-block y"
```

### After installation

The script will display:
```
PANEL ACCESS:
  URL:      https://mypanel.duckdns.org/xT8nQ4vLp9/
  Username: xT8nQ4vLp9
  Password: mK3rP6wN8z

DOMAINS:
  Panel:    mypanel.duckdns.org
  REALITY:  myreality.duckdns.org

ROUTING:
  Ad blocking:   ENABLED
  RU routing:    ENABLED
  QUIC block:    ENABLED
```

**Save these credentials!**

## Documentation

### Creating a REALITY inbound

In the 3X-UI panel:

1. **Inbounds** -> **Add Inbound**
2. **Settings**:
   - Protocol: `vless`
   - Port: `8443`
   - Transmission: `tcp`
   - Security: `reality`
3. **TCP Settings**:
   - Enable **Proxy Protocol**
4. **External Proxy**:
   - Domain: `mypanel.duckdns.org` (your panel domain)
   - Port: `443`
5. **REALITY Settings**:
   - Dest: `myreality.duckdns.org:9443` (your reality domain)
   - SNI: `myreality.duckdns.org`
   - Generate certificates
6. **Save**

### Telegram bot

1. **Settings** -> **Telegram Bot**
2. Create a bot via [@BotFather](https://t.me/botfather)
3. Paste the Bot Token
4. Add your Telegram ID (via [@userinfobot](https://t.me/userinfobot))
5. Save

The Telegram bot domain fix is already applied — the bot will generate correct links.

### Management

```bash
x-ui              # Main menu
x-ui start        # Start
x-ui stop         # Stop
x-ui restart      # Restart
x-ui status       # Status
x-ui update       # Update
```

### Changing SSH port (recommended)

```bash
nano /etc/ssh/sshd_config
# Change: Port 22 -> Port 2222

ufw allow 2222/tcp
ufw reload
systemctl restart ssh

# Connect:
ssh root@server -p 2222
```

## Routing customization

Config location: `/etc/x-ui/routing/config.json`

```bash
nano /etc/x-ui/routing/config.json
systemctl restart x-ui
```

## Troubleshooting

### Connection not working

```bash
systemctl status x-ui nginx
journalctl -u x-ui -f
tail -f /var/log/nginx/error.log
```

### Telegram bot wrong links

```bash
sqlite3 /etc/x-ui/x-ui.db "SELECT key, value FROM settings WHERE key LIKE '%Domain%';"
```

### REALITY not connecting

Checklist:
- Port = `8443`
- Proxy Protocol enabled
- External Proxy: domain + port 443
- Dest = `reality_domain:9443`
- SNI = reality domain
- Certificates generated

## VPN clients (VLESS + REALITY)
- [v2rayNG](https://github.com/2dust/v2rayNG) — Android
- [FoXray](https://apps.apple.com/app/foxray/id6448898396) — iOS
- [v2rayN](https://github.com/2dust/v2rayN) — Windows
- [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) — macOS
- [Qv2ray](https://github.com/Qv2ray/Qv2ray) — Linux

## Useful links
- [DuckDNS](https://www.duckdns.org) — free domains
- [Let's Encrypt](https://letsencrypt.org/) — SSL certificates
- [3X-UI Docs](https://github.com/MHSanaei/3x-ui)
- [Xray Docs](https://xtls.github.io/)

## Credits

RouteRus is built on the work of:

| Author | Contribution |
|--------|-------------|
| [@crazy_day_admin](https://t.me/crazy_day_admin) | Original x-ui-pro: Nginx reverse proxy, SSL automation, REALITY setup, fake website, subscriptions |
| [@Corvus-Malus](https://github.com/Corvus-Malus) | Routing system: ad blocking, RU split-routing, QUIC blocking, GeoIP/GeoSite rules |

### Projects used
- [3X-UI by MHSanaei](https://github.com/MHSanaei/3x-ui) — Web panel
- [Xray-core by XTLS](https://github.com/XTLS/Xray-core) — VPN engine
- [REALITY Protocol](https://github.com/XTLS/REALITY) — Obfuscation
- [v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) — GeoIP/GeoSite

## License

MIT License. See [LICENSE](LICENSE).

## Disclaimer

For legal use only. Users are responsible for compliance with applicable laws.

## Support

- [GitHub Discussions](https://github.com/anfixit/routerus/discussions)
- [Issues](https://github.com/anfixit/routerus/issues)
- [Telegram: @crazy_day_admin](https://t.me/crazy_day_admin)

## Roadmap

### Done
- [x] Automated installation
- [x] REALITY support
- [x] Advanced routing
- [x] Ad blocking
- [x] Telegram bot fix
- [x] SSL automation
- [x] BBR optimization

### Planned
- [ ] WebSocket inbound
- [ ] Cloudflare integration (non-REALITY)
- [ ] Web UI for routing
- [ ] Auto-backup
- [ ] Monitoring dashboard
- [ ] Multi-server
- [ ] Docker version
