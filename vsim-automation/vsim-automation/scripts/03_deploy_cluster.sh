#!/usr/bin/env bash
# =============================================================================
# 03_deploy_cluster.sh - Create a local Kubernetes cluster (kind) and deploy
# the manifests in k8s/.  Idempotent: reuses an existing cluster and uses
# 'kubectl apply' so re-runs only change what differs.
# =============================================================================
source "$(dirname "$0")/../lib/common.sh"

preflight() {
  for tool in docker kind kubectl; do
    have "$tool" || die "'$tool' not found. Run scripts/01_install_services.sh first."
  done
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start it and make sure your user is in the 'docker' group (try 'newgrp docker')."
}

create_cluster() {
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    log_info "Cluster '$CLUSTER_NAME' already exists; reusing"; return
  fi
  local cfg; cfg="$(mktemp)"
  # Map the host port to the NodePort so the app is reachable from the host.
  cat > "$cfg" <<CFG
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: ${NODE_PORT}
        hostPort: ${HOST_PORT}
        protocol: TCP
CFG
  log_info "Creating kind cluster '$CLUSTER_NAME'"
  if ! retry run kind create cluster --name "$CLUSTER_NAME" --config "$cfg" --wait 120s; then
    rm -f "$cfg"; die "Cluster creation failed (see log)."
  fi
  rm -f "$cfg"
}

deploy_manifests() {
  local ctx="kind-${CLUSTER_NAME}"
  log_info "Deploying manifests to context $ctx"
  # Render placeholders (namespace, nodeport) with sed - no extra tools needed.
  local rendered f; rendered="$(mktemp -d)"
  for f in "$PROJECT_ROOT"/k8s/*.yaml; do
    sed -e "s/__NAMESPACE__/${K8S_NAMESPACE}/g" -e "s/__NODE_PORT__/${NODE_PORT}/g" \
        "$f" > "$rendered/$(basename "$f")"
  done
  # 'kubectl apply -f <dir>' processes files alphabetically: namespace (00_) first.
  if ! run kubectl --context "$ctx" apply -f "$rendered"; then
    rm -rf "$rendered"; die "kubectl apply failed (see log)."
  fi
  rm -rf "$rendered"
  log_info "Waiting for rollout (timeout $ROLLOUT_TIMEOUT)"
  if ! run kubectl --context "$ctx" -n "$K8S_NAMESPACE" rollout status deployment/vsim-web --timeout="$ROLLOUT_TIMEOUT"; then
    kubectl --context "$ctx" -n "$K8S_NAMESPACE" get pods >>"$LOG_FILE" 2>&1 || true
    die "Deployment did not become ready; pod status written to log."
  fi
}

main() {
  load_config
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] would create kind cluster '$CLUSTER_NAME' and apply k8s/*.yaml"; return
  fi
  preflight
  create_cluster
  deploy_manifests
  log_info "Cluster deployment complete: http://localhost:${HOST_PORT}"
}
main "$@"
