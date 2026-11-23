#!/usr/bin/env bash
# =============================================================================
# teardown.sh - Remove the cluster created by this project (clean rollback).
# =============================================================================
source "$(dirname "$0")/../lib/common.sh"
main() {
  load_config
  if have kind && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    log_info "Deleting kind cluster '$CLUSTER_NAME'"
    run kind delete cluster --name "$CLUSTER_NAME"
  else
    log_info "Cluster '$CLUSTER_NAME' not found; nothing to do"
  fi
  log_info "Teardown complete (installed packages and /etc changes are left in place)"
}
main "$@"
