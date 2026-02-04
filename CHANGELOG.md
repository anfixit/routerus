# Changelog

All notable changes to RouteRus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-04

### Added
- 🎉 Initial release of RouteRus
- ✅ Automated 3X-UI Pro installation
- ✅ VLESS + REALITY protocol support
- ✅ Advanced routing configuration
  - Ad/tracker blocking
  - Russian domain direct routing
  - QUIC/HTTP3 blocking for non-RU IPs
  - GeoIP/GeoSite based routing
- ✅ SSL certificate automation (Let's Encrypt)
- ✅ Nginx reverse proxy configuration
- ✅ Fake website for masking
- ✅ UFW firewall setup
- ✅ BBR optimization
- ✅ System update automation
- ✅ Telegram bot domain fix
- ✅ DuckDNS support documentation
- ✅ Modular script architecture
- ✅ Comprehensive README with thanks to contributors

### Changed
- 🔄 Refactored from monolithic script to modular structure
- 🔄 Updated to use latest 3X-UI from GitHub API
- 🔄 Enhanced routing rules based on Corvus-Malus work

### Fixed
- 🐛 Fixed Telegram bot generating wrong VLESS links (subDomain/webDomain issue)
- 🐛 Fixed SSL certificate paths in database
- 🐛 Fixed REALITY inbound configuration

### Security
- 🔒 Improved firewall rules (only ports 22, 80, 443)
- 🔒 Random paths and ports generation
- 🔒 Proxy Protocol for REALITY connections

### Documentation
- 📚 Complete installation guide
- 📚 Routing configuration explained
- 📚 Troubleshooting section
- 📚 Thanks and attribution to original authors

## [Unreleased]

### Planned
- [ ] Automated WebSocket inbound creation
- [ ] Cloudflare integration for non-REALITY setups
- [ ] Web UI for routing management
- [ ] Backup automation
- [ ] Trojan protocol support
- [ ] Monitoring dashboard
- [ ] Multi-server management
- [ ] Docker version

---

## Attribution

Based on work by:
- [@crazy_day_admin](https://t.me/crazy_day_admin) - Original x-ui-pro script
- [@Corvus-Malus](https://github.com/Corvus-Malus) - Advanced routing configuration
