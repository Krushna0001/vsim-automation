#!/usr/bin/env bash
# =============================================================================
# 02_configure_network.sh - Kernel networking, firewall and hosts-file setup.
#   * loads br_netfilter and enables IP forwarding (needed by Kubernetes)
#   * opens HOST_PORT in ufw (if ufw is present and FIREWALL_ENABLE=true)
#   * adds a local DNS name for the platform to /etc/hosts
# Idempotent: re-running makes no duplicate changes.
# =============================================================================
source "$(dirname "$0")/../lib/common.sh"

SYSCTL_FILE=/etc/sysctl.d/99-vsim.conf
MODULES_FILE=/etc/modules-load.d/vsim.conf

configure_kernel() {
  log_info "Configuring kernel networking parameters"
  if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY-RUN] would write $SYSCTL_FILE"; return; fi
  run $SUDO modprobe br_netfilter || log_warn "br_netfilter unavailable (container/WSL?). Continuing."
  printf 'br_netfilter\n' | $SUDO tee "$MODULES_FILE" >/dev/null
  $SUDO tee "$SYSCTL_FILE" >/dev/null <<SYS
# Managed by vsim-automation
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYS
  # Failures on read-only kernel settings (containers) are non-fatal
  run $SUDO sysctl --system || log_warn "sysctl could not be fully applied."
}

configure_firewall() {
  if [[ "$FIREWALL_ENABLE" != "true" ]]; then log_info "Firewall configuration disabled"; return; fi
  if ! have ufw; then log_info "ufw not installed; skipping firewall rules"; return; fi
  log_info "Allowing TCP port $HOST_PORT in ufw"
  run $SUDO ufw allow "${HOST_PORT}/tcp"      # ufw ignores duplicate rules
}

configure_hosts() {
  local entry="127.0.0.1 ${HOSTS_ENTRY_NAME}"
  if grep -qE "[[:space:]]${HOSTS_ENTRY_NAME}([[:space:]]|\$)" /etc/hosts 2>/dev/null; then
    log_info "/etc/hosts already contains ${HOSTS_ENTRY_NAME}"; return
  fi
  log_info "Adding '$entry' to /etc/hosts"
  if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY-RUN] would append hosts entry"; return; fi
  backup_file /etc/hosts
  echo "$entry" | $SUDO tee -a /etc/hosts >/dev/null
}

main() {
  load_config
  setup_privileges
  configure_kernel
  configure_firewall
  configure_hosts
  log_info "Network configuration complete"
}
main "$@"
