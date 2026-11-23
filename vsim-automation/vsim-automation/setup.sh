#!/usr/bin/env bash
# =============================================================================
# setup.sh - Main entry point. Runs every automation step in order and stops
# at the first failure.  Usage: ./setup.sh [options]   (see --help)
# =============================================================================
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<USAGE
Usage: $0 [options]
  --dry-run        Show what would be done without changing the system
  --skip-install   Skip step 01 (tools already installed)
  --skip-network   Skip step 02 (kernel/firewall/hosts)
  --verbose        Print debug output to the console
  --config FILE    Use an alternative config file
  --teardown       Delete the cluster and exit
  -h, --help       Show this help
USAGE
}

export DRY_RUN=false VERBOSE=false
SKIP_INSTALL=false; SKIP_NETWORK=false; TEARDOWN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --skip-install) SKIP_INSTALL=true ;;
    --skip-network) SKIP_NETWORK=true ;;
    --verbose) VERBOSE=true ;;
    --config) [[ $# -ge 2 ]] || { echo "--config needs a file" >&2; exit 2; }; export CONFIG_FILE="$2"; shift ;;
    --teardown) TEARDOWN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"   # also exports LOG_FILE for the child scripts

if [[ "$TEARDOWN" == "true" ]]; then bash "$ROOT/scripts/teardown.sh"; exit $?; fi

log_info "=== vsim setup started (dry-run=$DRY_RUN) | log: $LOG_FILE ==="
declare -a STEPS=()
if [[ "$SKIP_INSTALL" != "true" ]]; then STEPS+=("01_install_services.sh"); fi
if [[ "$SKIP_NETWORK" != "true" ]]; then STEPS+=("02_configure_network.sh"); fi
STEPS+=("03_deploy_cluster.sh" "04_validate.sh")

for step in "${STEPS[@]}"; do
  log_info "--- Running $step ---"
  if ! bash "$ROOT/scripts/$step"; then
    log_error "Step $step FAILED. Aborting. Fix the problem and re-run (all steps are idempotent)."
    log_error "Log file: $LOG_FILE"
    exit 1
  fi
done
log_info "=== vsim setup finished successfully ==="
