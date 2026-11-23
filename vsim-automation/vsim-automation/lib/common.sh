# shellcheck shell=bash
# =============================================================================
# common.sh - Shared helpers: logging, error handling, retry, dry-run, config.
# Source this file; do not execute it.
# =============================================================================
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
mkdir -p "$LOG_DIR"
# One log file per run; setup.sh exports it so all step scripts append to it.
export LOG_FILE="${LOG_FILE:-$LOG_DIR/vsim_$(date +%Y%m%d_%H%M%S).log}"
export DRY_RUN="${DRY_RUN:-false}"
export VERBOSE="${VERBOSE:-false}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/config/env.conf}"
SUDO=""

# ---------------------------------------------------------------- logging ----
_log() {
  local level="$1"; shift
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') [$level] [$(basename "$0")] $*"
  echo "$line" >> "$LOG_FILE"                       # always persisted
  case "$level" in
    ERROR) echo "$line" >&2 ;;
    DEBUG) if [[ "$VERBOSE" == "true" ]]; then echo "$line"; fi ;;
    *)     echo "$line" ;;
  esac
}
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_debug() { _log DEBUG "$@"; }

# ---------------------------------------------------------- error handling ---
# Any unhandled failure reports the exact line and command, then exits.
on_error() {
  local rc="$1" line="$2" cmd="$3"
  log_error "Unexpected failure (exit $rc) at line $line: $cmd"
  log_error "See full log: $LOG_FILE"
  exit "$rc"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

die() { log_error "$*"; exit 1; }

# ---------------------------------------------------------------- helpers ----
# run <cmd...>: execute a command, capture its output in the log file,
# honour DRY_RUN, and report failures clearly.
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] $*"
    return 0
  fi
  log_debug "exec: $*"
  local rc=0
  "$@" >>"$LOG_FILE" 2>&1 || rc=$?
  if (( rc != 0 )); then
    log_error "Command failed (exit $rc): $*"
    return "$rc"
  fi
}

# retry <cmd...>: retry flaky operations (downloads, API calls).
retry() {
  local attempt=1 max="${RETRY_ATTEMPTS:-3}" delay="${RETRY_DELAY:-5}"
  until "$@"; do
    if (( attempt >= max )); then
      log_error "Giving up after $attempt attempts: $*"
      return 1
    fi
    log_warn "Attempt $attempt/$max failed; retrying in ${delay}s: $*"
    sleep "$delay"; attempt=$((attempt + 1))
  done
}

have() { command -v "$1" >/dev/null 2>&1; }

# Sets $SUDO to "" when root, "sudo" otherwise; dies if privileges are missing.
setup_privileges() {
  if [[ $EUID -eq 0 ]]; then SUDO=""
  elif have sudo; then SUDO="sudo"
  elif [[ "$DRY_RUN" == "true" ]]; then SUDO="sudo"
  else die "Root privileges required: run as root or install sudo."
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

# Load config.  Fails early with a clear message if the file is missing.
load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  log_debug "Loaded config: $CONFIG_FILE"
}

# Back up a file once before we modify it (safe rollback).
backup_file() {
  local f="$1"
  if [[ -f "$f" && ! -f "$f.vsim.bak" ]]; then
    run $SUDO cp -p "$f" "$f.vsim.bak"
  fi
}
