#!/usr/bin/env bash
# =============================================================================
# 01_install_services.sh - Install Docker, kubectl, kind and base utilities.
# Idempotent: tools that are already installed are skipped.
# Supported OS: Debian / Ubuntu (apt). For others see ansible/.
# =============================================================================
source "$(dirname "$0")/../lib/common.sh"

install_base_packages() {
  have apt-get || die "Only apt-based systems are supported by this script."
  log_info "Installing base packages"
  run $SUDO apt-get update -y
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ca-certificates curl git jq iproute2 iptables
}

install_docker() {
  if have docker; then log_info "Docker already installed: $(docker --version)"; return; fi
  log_info "Installing Docker"
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  if have systemctl && [[ -d /run/systemd/system ]]; then
    run $SUDO systemctl enable --now docker
  else
    log_warn "systemd not detected; start the Docker daemon manually."
  fi
  if [[ $EUID -ne 0 ]]; then
    run $SUDO usermod -aG docker "$USER"
    log_warn "Added $USER to 'docker' group. Re-login (or 'newgrp docker') before step 03."
  fi
}

# download_binary <url> <dest>
download_binary() {
  local url="$1" dest="$2" tmp
  tmp="$(mktemp)"
  log_info "Downloading $url"
  retry curl -fsSL --connect-timeout 15 -o "$tmp" "$url" || { rm -f "$tmp"; die "Download failed: $url"; }
  run $SUDO install -m 0755 "$tmp" "$dest"
  rm -f "$tmp"
}

install_kubectl() {
  if have kubectl; then log_info "kubectl already installed"; return; fi
  local arch url
  arch="$(detect_arch)"
  url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY-RUN] would install kubectl $KUBECTL_VERSION"; return; fi
  download_binary "$url" /usr/local/bin/kubectl
  # Integrity check against the official published checksum
  local expected actual
  expected="$(curl -fsSL "${url}.sha256")"
  actual="$(sha256sum /usr/local/bin/kubectl | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "kubectl checksum mismatch (expected $expected, got $actual)"
  log_info "kubectl $KUBECTL_VERSION installed and checksum verified"
}

install_kind() {
  if have kind; then log_info "kind already installed: $(kind version)"; return; fi
  local arch url
  arch="$(detect_arch)"
  url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${arch}"
  if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY-RUN] would install kind $KIND_VERSION"; return; fi
  download_binary "$url" /usr/local/bin/kind
  log_info "kind $KIND_VERSION installed"
}

main() {
  load_config
  setup_privileges
  install_base_packages
  install_docker
  install_kubectl
  install_kind
  log_info "Service installation complete"
}
main "$@"
