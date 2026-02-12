# Changelog

All notable changes to RouteRus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Automated WebSocket inbound creation
- Cloudflare integration for non-REALITY setups
- Web UI for routing management
- Backup automation
- Trojan protocol support
- Monitoring dashboard
- Multi-server management
- Docker version

## [1.0.1] - 2026-02-12

### Changed
- Rewrote all shell scripts to follow Google Shell Style Guide / ShellCheck best practices
- Replaced repetitive source/download blocks in install.sh with data-driven `load_module()` + steps array
- Moved `show_help()` before argument parsing so `--help` works correctly
- Added `--long-options` support alongside legacy `-single-dash` options
- Renamed helper functions for clarity (`get_port` -> `get_random_port`, `make_port` -> `make_free_port`)
- Cleaned up .gitignore (removed irrelevant Python/Node sections)
- Rewrote README.md in English, removed excessive emoji
- Simplified STRUCTURE.md and CONTRIBUTING.md
- Updated CHANGELOG.md to plain text format

### Security
- Replaced predictable `/tmp` paths with `mktemp -d` (prevents symlink attacks)
- Added download verification for remote scripts (shebang + non-empty check)
- Added `validate_domain()` and `validate_yn()` for CLI argument sanitization
- Hardened `cleanup.sh`: existence checks before `rm -rf`, `find -delete` for nginx dirs
- Extended `trap` to catch EXIT + INT + TERM signals
- Pinned GitHub Actions to exact commit SHAs (supply chain protection)
- Added `permissions: contents: read` to CI workflow (least privilege)
- Added security warning to `.env.example`

### Fixed
- All 12 placeholder scripts now define the functions `install.sh` expects
  (previously referenced undefined `${script}` variable)
- Removed unnecessary `export -f` from helpers.sh (redundant when scripts are sourced)

### Added
- `.editorconfig` for consistent formatting across editors
- `.shellcheckrc` for project-wide ShellCheck configuration

## [1.0.0] - 2026-02-04

### Added
- Initial release of RouteRus
- Automated 3X-UI Pro installation
- VLESS + REALITY protocol support
- Advanced routing configuration
  - Ad/tracker blocking
  - Russian domain direct routing
  - QUIC/HTTP3 blocking for non-RU IPs
  - GeoIP/GeoSite based routing
- SSL certificate automation (Let's Encrypt)
- Nginx reverse proxy configuration
- Fake website for masking
- UFW firewall setup
- BBR optimization
- System update automation
- Telegram bot domain fix
- DuckDNS support documentation
- Modular script architecture

### Changed
- Refactored from monolithic script to modular structure
- Updated to use latest 3X-UI from GitHub API
- Enhanced routing rules based on Corvus-Malus work

### Fixed
- Telegram bot generating wrong VLESS links (subDomain/webDomain issue)
- SSL certificate paths in database
- REALITY inbound configuration

---

## Attribution

Based on work by:
- [@crazy_day_admin](https://t.me/crazy_day_admin) - Original x-ui-pro script
- [@Corvus-Malus](https://github.com/Corvus-Malus) - Advanced routing configuration
