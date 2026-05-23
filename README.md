# esp-init

**ESP-IDF installer and project bootstrap** for Linux.

Repository: [github.com/fzappa/esp-init](https://github.com/fzappa/esp-init)

This script helps you install [ESP-IDF](https://github.com/espressif/esp-idf) without cloning the full repository up front. You pick a **release version** and **chip targets** first; only then it downloads a **shallow clone** and runs `install.sh` for the targets you chose.

## Features

- **List versions before download** — uses `git ls-remote` (kilobytes, not gigabytes)
- **List supported targets before download** — uses the GitHub API (`components/soc`)
- **Interactive setup** — pick version, pick targets (`a` or `1 2 3`), confirm, then install
- **Shallow clone** — `git clone --depth 1 --branch <tag>` for the selected release only
- **Selective toolchains** — `install.sh` runs for `all`, one chip, or several (e.g. `esp32,esp32s3`)
- **Multi-distro packages** — Arch / EndeavourOS, Debian / Ubuntu, Rocky / RHEL / Alma / CentOS / Fedora
- **New project scaffold** — copies Espressif `hello_world` into `~/esp/esp-projects/`

## Requirements

- `git`, `curl`, `python3`
- Network access to GitHub and Espressif download servers
- `sudo` for `--install-deps` (system packages)

## Install from GitHub

```bash
git clone https://github.com/fzappa/esp-init.git
cd esp-init
chmod +x esp-init.sh
```

## Quick start

```bash
# 1) System packages (once per machine)
./esp-init.sh --install-deps

# 2) Interactive install (recommended)
./esp-init.sh --setup

# 3) Activate ESP-IDF in every new shell
source ~/esp/esp-idf/export.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `--install-deps` | Install build dependencies for your distro |
| `--list-versions` | List available ESP-IDF release tags (no clone) |
| `--list-tags` | Alias for `--list-versions` |
| `--list-targets --tag v5.3.2` | List chips supported in that release (no clone) |
| `--list-targets` | List targets from an existing local `IDF_PATH` |
| `--setup` | Full interactive flow |
| `--setup --tag v5.3.2 --targets esp32` | Non-interactive install |
| `--setup --tag v5.3.2 --targets all` | Install toolchains for all listed targets |
| `--setup --tag v5.3.2 --targets esp32,esp32s3` | Multiple targets |
| `--new my_app esp32` | Create `~/esp/esp-projects/my_app` |
| `--help` | Show help |

## Interactive `--setup`

**Version menu**

- `N` — select version `N`, then choose targets
- `t N` — preview targets for version `N` only (no download)
- `l` — refresh version list
- `q` — quit

**Target selection** (after picking a version)

- `a` — all targets (`install.sh all`)
- `1` — first target in the list (often `esp32`)
- `1 11` or `1,11` — multiple targets by number

Example:

```text
Supported targets — ESP-IDF v5.3.2
   1) esp32
   2) esp32s3
   ...

Targets [a]: 1 2
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IDF_PATH` | `~/esp/esp-idf` | Where ESP-IDF is cloned |
| `WORKDIR` | `~/esp/esp-projects` | New projects from `--new` |
| `TAG_FILTER` | `v[0-9]*` | Filter release tags |
| `MAX_TAGS_LIST` | `40` | Max tags shown in the menu |
| `IDF_REPO` | Espressif GitHub URL | Override IDF repository |

## Migration from the old `esp-init`

| Old (v1) | New (v2) |
|----------|----------|
| `./esp-init.sh --clone` | `./esp-init.sh --setup` |
| `./esp-init.sh --clone esp32` | `./esp-init.sh --setup --tag v5.3.2 --targets esp32` |
| Full `git clone --recursive` immediately | Shallow clone **after** you choose version and targets |
| Ubuntu-only `--install-deps` | Arch, Debian/Ubuntu, Rocky/RHEL/Fedora |

`--clone` is deprecated and prints a hint to use `--setup`.

## Create a new project

```bash
source ~/esp/esp-idf/export.sh
./esp-init.sh --new my_sensor esp32
cd ~/esp/esp-projects/my_sensor
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor
```

## Typical layout

```text
~/esp/
├── esp-idf/          # ESP-IDF (shallow clone at chosen tag)
└── esp-projects/
    └── my_sensor/    # Your apps (--new)
```

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
