# RouteRus Project Structure

```
routerus/
├── .github/
│   └── workflows/
│       └── validate.yml          # CI: ShellCheck, JSON validation
│
├── configs/
│   └── routing/
│       ├── base-routing.json     # Base routing template
│       ├── adblock-rule.json     # Ad/tracker blocking rules
│       ├── ru-direct-rule.json   # Russian domain split-routing rules
│       └── quic-block-rule.json  # QUIC/HTTP3 blocking rules
│
├── scripts/
│   ├── helpers.sh               # Shared utility functions
│   ├── system-update.sh         # System package updates
│   ├── cleanup.sh               # Remove old installations
│   ├── domain-setup.sh          # Domain configuration
│   ├── routing-config.sh        # Routing feature selection
│   ├── install-packages.sh      # Dependency installation
│   ├── install-xui.sh           # 3X-UI installation
│   ├── ssl-setup.sh             # SSL certificate setup
│   ├── db-config.sh             # Database configuration
│   ├── setup-routing.sh         # Apply routing rules
│   ├── nginx-config.sh          # Nginx reverse proxy
│   ├── create-inbounds.sh       # Create VPN inbounds
│   ├── optimize.sh              # BBR and kernel optimization
│   ├── firewall.sh              # UFW firewall
│   ├── cron-setup.sh            # Automated cron tasks
│   ├── show-results.sh          # Display installation results
│   └── uninstall.sh             # Uninstall script
│
├── .editorconfig                # Editor formatting rules
├── .env.example                 # Configuration template
├── .gitattributes               # Git text handling
├── .gitignore                   # Git ignore rules
├── .shellcheckrc                # ShellCheck configuration
├── CHANGELOG.md                 # Version history
├── CONTRIBUTING.md              # Contribution guidelines
├── LICENSE                      # MIT license
├── README.md                    # Main documentation
├── STRUCTURE.md                 # This file
├── install.sh                   # Main installation orchestrator
└── quick-install.sh             # One-command installer
```

## Installation workflow

```
quick-install.sh -> downloads install.sh
  install.sh -> loads helpers.sh, then runs modules:
    1. system-update.sh
    2. cleanup.sh
    3. domain-setup.sh
    4. routing-config.sh
    5. install-packages.sh
    6. install-xui.sh
    7. ssl-setup.sh
    8. db-config.sh
    9. setup-routing.sh  (reads configs/routing/*.json)
    10. nginx-config.sh
    11. create-inbounds.sh
    12. optimize.sh
    13. firewall.sh
    14. cron-setup.sh
    15. show-results.sh
```

## Conventions

### Naming
- Script files: `kebab-case.sh`
- Functions: `snake_case`
- Variables: `UPPERCASE` for globals, `lowercase` for locals

### Code style
- All scripts start with `#!/bin/bash`
- Use `set -euo pipefail` where appropriate
- Quote all variable expansions: `"${var}"`
- Use `[[ ]]` instead of `[ ]` for conditionals
- Validate with `shellcheck` before committing

### Adding a new module
1. Create `scripts/new-module.sh` with a named function
2. Add the `module:function` entry to the `steps` array in `install.sh`
3. Update this file

### Adding routing rules
1. Create `configs/routing/new-rule.json`
2. Add assembly logic in `setup-routing.sh`
3. Add a toggle option in `routing-config.sh`

## CI/CD

GitHub Actions validates on every push:
- ShellCheck on all `.sh` files
- Bash syntax check (`bash -n`)
- JSON config validation (`jq empty`)
