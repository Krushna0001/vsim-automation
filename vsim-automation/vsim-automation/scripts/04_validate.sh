#!/usr/bin/env bash
# =============================================================================
# 04_validate.sh - Post-deployment verification. Exits non-zero if any check fails.
# =============================================================================
source "$(dirname "$0")/../lib/common.sh"
FAILED=0

check() {  # check "<description>" <command...>
  local desc="$1"; shift
  if "$@" >>"$LOG_FILE" 2>&1; then log_info "PASS  $desc"
  else log_error "FAIL  $desc"; FAILED=$((FAILED + 1)); fi
}

main() {
  load_config
  if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY-RUN] would validate installation"; return; fi
  local ctx="kind-${CLUSTER_NAME}"
  check "docker is available"   docker info
  check "kubectl is available"  kubectl version --client
  check "kind cluster exists"   bash -c "kind get clusters | grep -qx '$CLUSTER_NAME'"
  check "all nodes Ready"       kubectl --context "$ctx" wait --for=condition=Ready nodes --all --timeout=60s
  check "deployment available"  kubectl --context "$ctx" -n "$K8S_NAMESPACE" wait --for=condition=Available deployment/vsim-web --timeout=60s
  if have python3; then
    check "HTTP health check (python)" python3 "$PROJECT_ROOT/python/healthcheck.py" --url "http://localhost:${HOST_PORT}" --retries 5
  else
    check "HTTP health check (curl)"   curl -fsS --retry 5 --retry-delay 2 "http://localhost:${HOST_PORT}"
  fi
  if (( FAILED > 0 )); then die "$FAILED validation check(s) failed."; fi
  log_info "All validation checks passed"
}
main "$@"
