#!/usr/bin/env bash
#
# esp-init — ESP-IDF installer and project bootstrap
# Supports: Arch, EndeavourOS, Ubuntu, Debian, Rocky, RHEL, Alma, CentOS, Fedora
#
# Usage:
#   ./esp-init.sh --install-deps
#   ./esp-init.sh --list-versions
#   ./esp-init.sh --list-targets --tag v5.3.2
#   ./esp-init.sh --setup
#   ./esp-init.sh --setup --tag v5.3.2 --targets esp32
#   ./esp-init.sh --new my_project esp32
#   ./esp-init.sh --help
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

WORKDIR="${WORKDIR:-$HOME/esp/esp-projects}"
IDF_PATH="${IDF_PATH:-$HOME/esp/esp-idf}"
IDF_REPO="${IDF_REPO:-https://github.com/espressif/esp-idf.git}"
TAG_FILTER="${TAG_FILTER:-v[0-9]*}"
MAX_TAGS_LIST="${MAX_TAGS_LIST:-40}"

TAGS=()
REPLY_TARGETS=""

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

info() { echo "==> $*" >&2; }

prompt() {
  local msg="$1"
  local default="${2:-}"
  local reply
  if [[ -n "$default" ]]; then
    read -r -p "$msg [$default]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "$msg: " reply
    echo "$reply"
  fi
}

check_git() {
  command -v git &>/dev/null || die "Git is not installed."
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    local id="${ID:-unknown}"
    local like="${ID_LIKE:-}"

    case "$id" in
      arch|endeavouros) echo arch; return ;;
      ubuntu|debian|linuxmint|pop) echo debian; return ;;
      rocky|rhel|almalinux|centos|ol|eurolinux|scientific) echo rhel; return ;;
      fedora) echo rhel; return ;;
    esac

    case "$like" in
      *arch*) echo arch ;;
      *debian*|*ubuntu*) echo debian ;;
      *rhel*|*fedora*|*centos*) echo rhel ;;
      *) echo unknown ;;
    esac
  else
    echo unknown
  fi
}

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------

install_dependencies_arch() {
  info "Installing dependencies (pacman)..."
  sudo pacman -Syu --needed --noconfirm \
    git wget curl flex bison gperf python python-pip cmake ninja ccache \
    libffi openssl dfu-util libusb \
    2>/dev/null || sudo pacman -S --needed \
    git wget curl flex bison gperf python python-pip cmake ninja ccache \
    libffi openssl dfu-util libusb
}

install_dependencies_debian() {
  info "Installing dependencies (apt)..."
  sudo apt-get update
  sudo apt-get install -y \
    git wget curl flex bison gperf python3 python3-pip python3-venv \
    cmake ninja-build ccache libffi-dev libssl-dev dfu-util libusb-1.0-0
}

install_dependencies_rhel() {
  local pm="dnf"
  command -v dnf &>/dev/null || pm="yum"
  command -v "$pm" &>/dev/null || die "dnf/yum not found (Rocky/RHEL/CentOS/Fedora)."

  info "Installing dependencies ($pm)..."
  # EPEL: dfu-util and extras on Rocky/Alma/CentOS/RHEL
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
      rocky|rhel|almalinux|centos|ol)
        if ! rpm -q epel-release &>/dev/null; then
          info "Installing EPEL (recommended on ${NAME:-RHEL})..."
          sudo "$pm" install -y epel-release || true
        fi
        ;;
    esac
  fi

  sudo "$pm" makecache -y 2>/dev/null || true
  sudo "$pm" install -y \
    git wget curl flex bison gperf \
    python3 python3-pip python3-devel \
    cmake ninja-build ccache \
    libffi-devel openssl-devel \
    dfu-util libusb libusb-devel \
    patch which file
}

install_dependencies() {
  local os
  os="$(detect_os)"
  case "$os" in
    arch) install_dependencies_arch ;;
    debian) install_dependencies_debian ;;
    rhel) install_dependencies_rhel ;;
    *)
      die "Unsupported OS ($os). Supported: Arch, Debian/Ubuntu, Rocky/RHEL/Fedora. Install manually: git, python3, cmake, ninja, flex, bison, gperf, ccache, dfu-util, libusb."
      ;;
  esac
  info "System dependencies installed."
}

# ---------------------------------------------------------------------------
# ESP-IDF: remote queries (no clone) and shallow clone after selection
# ---------------------------------------------------------------------------

require_cmd() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}

list_tags_remote() {
  require_cmd git
  info "Fetching release tags from $IDF_REPO (no repository download)..."
  git ls-remote --tags "$IDF_REPO" 2>/dev/null |
    sed 's/.*refs\/tags\///' |
    grep -v '\^{}$' |
    grep -E '^v[0-9]' |
    sort -Vr |
    head -n "$MAX_TAGS_LIST"
}

fetch_tags_local() {
  [[ -d "$IDF_PATH/.git" ]] || return 0
  pushd "$IDF_PATH" >/dev/null
  git fetch --tags --force origin 2>/dev/null || git fetch --tags --force
  popd >/dev/null
}

list_tags_local() {
  pushd "$IDF_PATH" >/dev/null
  git tag -l "$TAG_FILTER" --sort=-version:refname 2>/dev/null | head -n "$MAX_TAGS_LIST"
  popd >/dev/null
}

tag_exists_remote() {
  local tag="$1"
  git ls-remote --tags "$IDF_REPO" 2>/dev/null |
    grep -qE "refs/tags/${tag}(\^\{\})?$"
}

load_tags_array() {
  TAGS=()
  mapfile -t TAGS < <(list_tags_remote)
  if [[ ${#TAGS[@]} -eq 0 ]] && [[ -d "$IDF_PATH/.git" ]]; then
    fetch_tags_local
    mapfile -t TAGS < <(list_tags_local)
  fi
  [[ ${#TAGS[@]} -gt 0 ]] || die "No versions found (filter: $TAG_FILTER). Check network and $IDF_REPO."
}

list_targets_for_tag_remote() {
  local tag="$1"
  [[ -n "$tag" ]] || die "Specify a version with --tag."
  require_cmd curl
  require_cmd python3
  tag_exists_remote "$tag" || die "Version not found on remote: $tag"

  local url="https://api.github.com/repos/espressif/esp-idf/contents/components/soc?ref=${tag}"
  local json
  json="$(curl -fsSL --connect-timeout 20 --max-time 60 "$url")" ||
    die "Failed to query GitHub API (version $tag)."

  printf '%s' "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, dict):
    sys.exit(1)
for e in sorted(data, key=lambda x: x['name']):
    n = e['name']
    if e.get('type') == 'dir' and (n.startswith('esp') or n == 'linux'):
        print(n)
" || die "Could not parse targets for $tag."
}

list_targets_for_tag_local() {
  local tag="$1"
  pushd "$IDF_PATH" >/dev/null
  git rev-parse "$tag^{commit}" &>/dev/null || die "Version not found locally: $tag"
  git ls-tree --name-only "$tag:components/soc" 2>/dev/null |
    grep -E '^(esp|linux)' | sort -u
  popd >/dev/null
}

list_targets_for_tag() {
  local tag="$1"
  if [[ -d "$IDF_PATH/.git" ]] &&
    git -C "$IDF_PATH" rev-parse "$tag^{commit}" &>/dev/null 2>&1; then
    list_targets_for_tag_local "$tag"
  else
    list_targets_for_tag_remote "$tag"
  fi
}

TARGETS=()

load_targets_array() {
  local tag="${1:-}"
  TARGETS=()
  if [[ -z "$tag" ]]; then
    [[ -d "$IDF_PATH/.git" ]] ||
      die "Repository not cloned. Use --list-targets --tag VERSION or run --setup."
    mapfile -t TARGETS < <(list_supported_targets)
  else
    mapfile -t TARGETS < <(list_targets_for_tag "$tag")
  fi
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=(esp32)
  fi
}

print_versions() {
  load_tags_array
  {
    echo ""
    echo "Available ESP-IDF versions (filter: $TAG_FILTER, up to $MAX_TAGS_LIST)"
    echo "Source: remote Git — repository not downloaded yet"
    echo "URL: $IDF_REPO"
    echo "------------------------------------------------------------"
    local i
    for i in "${!TAGS[@]}"; do
      printf "  %2d) %s\n" "$((i + 1))" "${TAGS[$i]}"
    done
    echo "------------------------------------------------------------"
    echo "Total: ${#TAGS[@]} version(s)"
    echo ""
    echo "Tip: list targets for a version without installing:"
    echo "  $SCRIPT_NAME --list-targets --tag ${TAGS[0]}"
    echo ""
  } >&2
}

print_targets() {
  local tag="${1:-}"
  local tag_label

  load_targets_array "$tag"
  if [[ -n "$tag" ]]; then
    tag_label="$tag"
  else
    tag_label="$(git -C "$IDF_PATH" describe --tags --exact-match 2>/dev/null ||
      git -C "$IDF_PATH" rev-parse --short HEAD 2>/dev/null || echo "current checkout")"
  fi

  {
    echo ""
    echo "Supported targets — ESP-IDF $tag_label"
    if [[ -n "$tag" ]] && [[ ! -d "$IDF_PATH/.git" ]]; then
      echo "(via GitHub API — repository not downloaded yet)"
    fi
    echo "------------------------------------------------------------"
    local i
    for i in "${!TARGETS[@]}"; do
      printf "  %2d) %s\n" "$((i + 1))" "${TARGETS[$i]}"
    done
    echo "------------------------------------------------------------"
    echo "Total: ${#TARGETS[@]} target(s)"
    if [[ -n "$tag" ]]; then
      echo "Examples:"
      echo "  $SCRIPT_NAME --setup --tag $tag --targets all"
      echo "  $SCRIPT_NAME --setup --tag $tag --targets esp32"
      echo "  $SCRIPT_NAME --setup --tag $tag --targets esp32,esp32s3"
    fi
    echo ""
  } >&2
}

preview_targets_for_version_index() {
  local idx="$1"
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#TAGS[@]} )); then
    echo "Invalid index: $idx" >&2
    return 1
  fi
  print_targets "${TAGS[$((idx - 1))]}"
}

# Parse user input for install.sh (all or esp32,esp32s3,...)
# Accepts: a | all | 3 | 1 2 3 | 1,2,3
parse_devices_choice() {
  local raw="$1"
  local normalized="${raw,,}"
  normalized="${normalized//,/ }"
  normalized="${normalized#"${normalized%%[![:space:]]*}"}"
  normalized="${normalized%"${normalized##*[![:space:]]}"}"

  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    a|all)
      REPLY_TARGETS="all"
      return 0
      ;;
  esac

  if [[ "$normalized" =~ ^[0-9]+$ ]]; then
    local idx="$normalized"
    if (( idx >= 1 && idx <= ${#TARGETS[@]} )); then
      REPLY_TARGETS="${TARGETS[$((idx - 1))]}"
      return 0
    fi
    return 1
  fi

  local out=() part
  read -ra parts <<<"$normalized"
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    if (( part >= 1 && part <= ${#TARGETS[@]} )); then
      out+=("${TARGETS[$((part - 1))]}")
    else
      return 1
    fi
  done

  ((${#out[@]} > 0)) || return 1
  REPLY_TARGETS="$(IFS=','; echo "${out[*]}")"
  return 0
}

prompt_devices_choice() {
  local tag="${1:-}"
  load_targets_array "$tag"
  print_targets "$tag"
  {
    echo "Select targets:"
    echo "  a          = all (install.sh all)"
    echo "  1          = target 1 only"
    echo "  1 2 3      = multiple (space or comma separated)"
    echo ""
  } >&2

  local dev_choice
  while true; do
    dev_choice="$(prompt "Targets" "a")"
    if parse_devices_choice "$dev_choice"; then
      if [[ "$REPLY_TARGETS" == "all" ]]; then
        info "Selected: all targets"
      else
        info "Selected: ${REPLY_TARGETS//,/ }"
      fi
      return 0
    fi
    echo "Invalid. Use 'a' or numbers from the list (e.g. 1 3 5)." >&2
  done
}

choose_tag_interactive() {
  REPLY_TARGETS=""
  load_tags_array

  while true; do
    print_versions
    {
      echo "Prompt commands:"
      echo "  N        = select version N (download happens at the end)"
      echo "  t N      = list targets for version N (no download)"
      echo "  l        = refresh version list"
      echo "  q        = quit"
      echo ""
    } >&2

    local choice
    choice="$(prompt "Choice")"
    choice="${choice//[[:space:]]/}"

    case "${choice,,}" in
      q|quit|exit)
        die "Cancelled by user."
        ;;
      l|list)
        continue
        ;;
      t*)
        local num="${choice#t}"
        preview_targets_for_version_index "$num" || true
        continue
        ;;
    esac

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TAGS[@]} )); then
      local selected="${TAGS[$((choice - 1))]}"
      info "Selected version: $selected"
      prompt_devices_choice "$selected"

      local confirm
      confirm="$(prompt "Confirm version $selected and targets above? (y/N)" "y")"
      if [[ "${confirm,,}" == y || "${confirm,,}" == yes ]]; then
        REPLY="$selected"
        return 0
      fi
      REPLY_TARGETS=""
      echo "Selection cancelled. Pick another version." >&2
      continue
    fi

    echo "Invalid option: $choice" >&2
  done
}

clone_idf_shallow() {
  local tag="$1"
  [[ -n "$tag" ]] || die "Tag not specified."

  if [[ -d "$IDF_PATH" ]] && [[ ! -d "$IDF_PATH/.git" ]]; then
    die "$IDF_PATH exists but is not a git repository. Remove it or set another IDF_PATH."
  fi

  if [[ -d "$IDF_PATH/.git" ]]; then
    local current=""
    current="$(git -C "$IDF_PATH" describe --tags --exact-match 2>/dev/null || true)"
    if [[ "$current" == "$tag" ]]; then
      info "ESP-IDF already at $tag — updating submodules..."
      pushd "$IDF_PATH" >/dev/null
      git submodule update --init --recursive
      popd >/dev/null
      return 0
    fi
    info "Switching local clone to $tag ..."
    pushd "$IDF_PATH" >/dev/null
    git fetch --depth 1 origin "tag ${tag}" 2>/dev/null || git fetch --tags --depth 1 origin 2>/dev/null || true
    git checkout "$tag"
    git submodule update --init --recursive
    popd >/dev/null
    return 0
  fi

  info "Downloading ESP-IDF $tag (shallow clone --depth 1, no full history)..."
  info "Destination: $IDF_PATH"
  mkdir -p "$(dirname "$IDF_PATH")"
  git clone --depth 1 --branch "$tag" --recursive "$IDF_REPO" "$IDF_PATH"
}

list_supported_targets() {
  pushd "$IDF_PATH" >/dev/null
  local targets=()

  if [[ -x tools/idf_tools.py ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && targets+=("$line")
  done < <(python tools/idf_tools.py list-targets 2>/dev/null || true)
  fi

  if [[ ${#targets[@]} -eq 0 ]] && [[ -d components/soc ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && targets+=("$line")
    done < <(ls -1 components/soc 2>/dev/null | grep -E '^(esp|linux)' | sort -u)
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    targets=(esp32)
  fi

  printf '%s\n' "${targets[@]}"
  popd >/dev/null
}

choose_targets_interactive() {
  local preview_tag="${1:-}"
  prompt_devices_choice "$preview_tag"
  REPLY="$REPLY_TARGETS"
}

setup_tools() {
  local targets_arg="$1"
  local py_path py_ver
  py_path="$(command -v python3)"
  py_ver="$("$py_path" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

  info "Running install.sh ($targets_arg) with $py_path (Python $py_ver)..."
  pushd "$IDF_PATH" >/dev/null
  if [[ "$targets_arg" == "all" ]]; then
    ./install.sh all
  else
    # shellcheck disable=SC2086
    ./install.sh ${targets_arg//,/ }
  fi
  popd >/dev/null

  {
    echo ""
    info "Install finished. Python virtualenv is tied to Python $py_ver"
    echo "  Expected venv: ~/.espressif/python_env/idf*_py${py_ver//./}_env"
    echo ""
    echo "Activate ESP-IDF (use the SAME python3 as above):"
    echo "  conda deactivate    # if you use conda"
    echo "  which python3 && python3 --version"
    echo "  source $IDF_PATH/export.sh"
    echo ""
    echo "If export.sh looks for py3.14_env but install used py3.12, deactivate conda"
    echo "or open a new shell without Python 3.14 on PATH."
  } >&2
}

run_setup() {
  local tag="${1:-}"
  local targets="${2:-}"

  check_git

  if [[ -z "$tag" ]]; then
    choose_tag_interactive
    tag="$REPLY"
    targets="${REPLY_TARGETS:-}"
  fi

  if [[ -z "$targets" ]]; then
    info "Select targets (online query; code download happens next):"
    choose_targets_interactive "$tag"
    targets="$REPLY_TARGETS"
  fi

  clone_idf_shallow "$tag"
  setup_tools "$targets"

  echo ""
  info "ESP-IDF $tag is ready."
}

# ---------------------------------------------------------------------------
# New project (hello_world template)
# ---------------------------------------------------------------------------

update_cmake_lists() {
  local project_dir="$1"
  local project_name="$2"
  local cmake="$project_dir/CMakeLists.txt"
  local main_cmake="$project_dir/main/CMakeLists.txt"

  if [[ -f "$cmake" ]]; then
    sed -i "s/project(.*)/project(${project_name})/" "$cmake"
  fi
  if [[ -f "$main_cmake" ]]; then
    sed -i 's/hello_world_main\.c/main.c/g' "$main_cmake" 2>/dev/null || true
    sed -i 's/"hello_world_main.c"/"main.c"/' "$main_cmake" 2>/dev/null || true
  fi
}

set_target_project() {
  local project_dir="$1"
  local target="$2"

  if [[ ! -f "$IDF_PATH/export.sh" ]]; then
    die "ESP-IDF not configured. Run: $SCRIPT_NAME --setup"
  fi
  # shellcheck disable=SC1090
  source "$IDF_PATH/export.sh"
  pushd "$project_dir" >/dev/null
  idf.py set-target "$target"
  popd >/dev/null
}

create_project() {
  local project_name="$1"
  local target="${2:-esp32}"
  local project_dir="$WORKDIR/$project_name"

  [[ -f "$IDF_PATH/export.sh" ]] || die "ESP-IDF not installed. Run: $SCRIPT_NAME --setup"
  [[ -d "$project_dir" ]] && die "Project already exists: $project_dir"

  local template="$IDF_PATH/examples/get-started/hello_world"
  [[ -d "$template" ]] || die "Template not found: $template"

  mkdir -p "$WORKDIR"
  cp -a "$template" "$project_dir"

  local main_src=""
  if [[ -f "$project_dir/main/hello_world_main.c" ]]; then
    main_src="$project_dir/main/hello_world_main.c"
  elif [[ -f "$project_dir/main/main.c" ]]; then
    main_src="$project_dir/main/main.c"
  fi
  [[ -n "$main_src" ]] && mv "$main_src" "$project_dir/main/main.c"

  update_cmake_lists "$project_dir" "$project_name"
  set_target_project "$project_dir" "$target"

  info "Project created: $project_dir (target: $target)"
  echo "  cd $project_dir"
  echo "  source $IDF_PATH/export.sh"
  echo "  idf.py build"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

display_help() {
  cat <<EOF
${SCRIPT_NAME} — ESP-IDF installer (Arch, Debian/Ubuntu, Rocky/RHEL/Fedora)

Commands:
  --install-deps              Install system packages
  --list-versions             List release tags via remote Git (no clone)
  --list-tags                 Alias for --list-versions
  --list-targets --tag VER    List supported targets via GitHub API (no clone)
  --list-targets              List targets from local IDF_PATH checkout
  --setup                     Interactive: version → targets → shallow clone → install
  --setup --tag v5.3.2
  --setup --tag v5.3.2 --targets esp32
  --setup --tag v5.3.2 --targets all
  --setup --tag v5.3.2 --targets esp32,esp32s3
  --new NAME [target]         Create project under ~/esp/esp-projects/NAME
  --clone [targets]           Deprecated — use --setup instead
  --help

Environment:
  IDF_PATH      (default: ~/esp/esp-idf)
  WORKDIR       (default: ~/esp/esp-projects)
  TAG_FILTER    (default: v[0-9]*)
  MAX_TAGS_LIST (default: 40)

Examples:
  ./${SCRIPT_NAME} --install-deps
  ./${SCRIPT_NAME} --list-versions
  ./${SCRIPT_NAME} --list-targets --tag v5.3.2
  ./${SCRIPT_NAME} --setup
  ./${SCRIPT_NAME} --setup --tag v5.3.2 --targets esp32
  ./${SCRIPT_NAME} --new my_sensor esp32

--setup workflow (saves disk and time):
  1. List versions (git ls-remote, a few KB)
  2. Pick targets (GitHub API, a few KB)
  3. Shallow clone of the chosen tag only (--depth 1)
  4. install.sh for selected chips only

Interactive menu: t 3 = preview targets for version 3 | pick targets: a or 1 2 3

After setup:
  source ~/esp/esp-idf/export.sh
  cd ~/esp/esp-projects/my_app && idf.py build
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 ]]; then
    display_help
    exit 0
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    --install-deps)
      install_dependencies
      ;;
    --list-versions|--list-tags)
      check_git
      print_versions
      ;;
    --list-targets)
      check_git
      local list_tag=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --tag) list_tag="$2"; shift 2 ;;
          *) die "Unknown option: $1 (use --tag VERSION)" ;;
        esac
      done
      if [[ -n "$list_tag" ]]; then
        print_targets "$list_tag"
      else
        [[ -d "$IDF_PATH/.git" ]] || die "IDF not cloned. Run --setup first."
        print_targets ""
      fi
      ;;
    --setup)
      local tag="" targets=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --tag) tag="$2"; shift 2 ;;
          --targets) targets="$2"; shift 2 ;;
          --list-versions|--list-tags)
            check_git
            print_versions
            exit 0
            ;;
          --list-targets)
            [[ -n "${2:-}" ]] || die "Use: $SCRIPT_NAME --list-targets --tag v5.3.2"
            check_git
            print_targets "$2"
            shift 2
            ;;
          *) die "Unknown option: $1" ;;
        esac
      done
      run_setup "$tag" "$targets"
      ;;
    --clone)
      echo "Warning: --clone is deprecated. Use --setup instead." >&2
      echo "  Old: $SCRIPT_NAME --clone esp32" >&2
      echo "  New: $SCRIPT_NAME --setup --tag v5.3.2 --targets esp32" >&2
      echo "  Or:  $SCRIPT_NAME --setup   (interactive)" >&2
      exit 1
      ;;
    --new)
      [[ $# -ge 1 ]] || die "Specify a project name."
      check_git
      create_project "$1" "${2:-esp32}"
      ;;
    --help|-h)
      display_help
      ;;
    *)
      die "Invalid command: $cmd (use --help)"
      ;;
  esac
}

main "$@"
