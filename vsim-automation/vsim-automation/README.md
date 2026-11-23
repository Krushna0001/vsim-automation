# Virtual Simulation Platform – Environment Automation (Week 2 Pilot)

Automation scripts that build a repeatable local environment for a virtual
simulation platform: they **install services**, **configure networking**, and
**deploy Kubernetes manifests**, with logging, error handling and validation.

## 1. Critical tasks automated

| # | Task | Why it matters | Where |
|---|------|----------------|-------|
| 1 | Install Docker, kubectl, kind, base tools | Identical toolchain on every machine (versions pinned) | `scripts/01_install_services.sh` |
| 2 | Kernel networking, firewall, hosts entry | Kubernetes needs IP forwarding and `br_netfilter` | `scripts/02_configure_network.sh` |
| 3 | Create cluster and deploy manifests | Container orchestration set up from code | `scripts/03_deploy_cluster.sh`, `k8s/` |
| 4 | Post-deployment verification | Proves the setup actually works | `scripts/04_validate.sh`, `python/healthcheck.py` |
| 5 | Clean rollback | Reset environments quickly | `scripts/teardown.sh` |
| 6 | Alternative in YAML (Ansible) | Same host configuration as declarative code | `ansible/playbook.yml` |

## 2. Project structure

```
vsim-automation/
├── setup.sh                  # main entry point (runs steps 01-04)
├── config/env.conf           # all settings (overridable via env vars)
├── lib/common.sh             # logging, error trap, retry, dry-run helpers
├── scripts/
│   ├── 01_install_services.sh
│   ├── 02_configure_network.sh
│   ├── 03_deploy_cluster.sh
│   ├── 04_validate.sh
│   └── teardown.sh
├── k8s/                      # namespace, configmap, deployment, service
├── python/healthcheck.py     # HTTP health probe with retries
├── ansible/                  # playbook.yml + inventory.ini
└── logs/                     # one timestamped log per run
```

## 3. Requirements

* Linux (Debian/Ubuntu, x86_64 or arm64), `bash` 4+, `sudo` rights, internet access
* `python3` (optional, used for the health check; falls back to `curl`)
* Ansible (optional, only for the playbook; needs `community.general` and `ansible.posix` collections)

## 4. Usage

```bash
cd vsim-automation
chmod +x setup.sh scripts/*.sh        # if permissions were lost during unzip

./setup.sh --dry-run                  # 1. preview – changes nothing
./setup.sh                            # 2. full setup
./setup.sh --skip-install --skip-network   # re-deploy only
./setup.sh --teardown                 # remove the cluster
```

| Option | Meaning |
|--------|---------|
| `--dry-run` | Print every action without executing it |
| `--skip-install` / `--skip-network` | Skip step 01 / 02 |
| `--verbose` | Show debug messages on the console |
| `--config FILE` | Use a different config file |
| `--teardown` | Delete the cluster and exit |

Each step can also be run on its own, e.g. `./scripts/04_validate.sh`.

**Important:** step 01 adds your user to the `docker` group. If step 03 reports
that the Docker daemon is unreachable, run `newgrp docker` (or log out/in) and
then `./setup.sh --skip-install`.

### Configuration

Edit `config/env.conf` or override per run:

```bash
CLUSTER_NAME=staging HOST_PORT=9090 ./setup.sh
```

After a successful run the platform is available at `http://localhost:8080`
(and `http://vsim.local:8080`).

### Ansible alternative

```bash
cd ansible
ansible-galaxy collection install community.general ansible.posix
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass --check   # dry run
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```

## 5. Reliability features

* **Strict mode** – `set -Eeuo pipefail` in every script.
* **Error trap** – any unexpected failure logs the exit code, line number and
  command, then stops.
* **Explicit error handling** – pre-flight checks (docker/kind/kubectl present,
  daemon reachable), clear `die` messages with hints, cleanup of temp files.
* **Retry logic** – downloads and cluster creation retry (`RETRY_ATTEMPTS`,
  `RETRY_DELAY`).
* **Idempotency** – safe to re-run: installed tools are skipped, the existing
  cluster is reused, `kubectl apply` is declarative, hosts/sysctl changes are
  not duplicated.
* **Integrity** – kubectl download is verified against its official SHA-256.
* **Backups** – `/etc/hosts` is copied to `/etc/hosts.vsim.bak` before edits.
* **Dry-run mode** – review changes before applying them.
* **Pinned versions** – kind, kubectl and the nginx image are versioned.
* **Health-gated deployment** – readiness/liveness probes, rollout wait with
  timeout, then validation checks.

## 6. Logging and troubleshooting

* Console output and a full log go to `logs/vsim_<timestamp>.log`. The log
  also captures the stdout/stderr of every underlying command.
* Format: `YYYY-MM-DD HH:MM:SS [LEVEL] [script] message`.
* Typical problems:

| Symptom | Fix |
|---------|-----|
| `Docker daemon not reachable` | Start Docker; `newgrp docker`; or run with sudo |
| `Download failed` | Check internet/proxy; re-run (retries are automatic) |
| Port already in use | Set another `HOST_PORT` and re-create the cluster (`--teardown`) |
| Rollout timeout | Check pod status at the end of the log; `kubectl -n vsim get pods` |
| `br_netfilter unavailable` | Expected in containers/WSL; a warning only |

## 7. Script descriptions

* **setup.sh** – parses options, shares one log file, runs steps in order,
  aborts on the first failure with a clear message.
* **lib/common.sh** – `log_*`, `run` (dry-run aware, logs output), `retry`,
  `die`, `backup_file`, `load_config`, privilege and architecture detection.
* **01_install_services.sh** – apt base packages, Docker (+ service enable),
  kubectl (checksum verified) and kind.
* **02_configure_network.sh** – `br_netfilter`, sysctl file
  `/etc/sysctl.d/99-vsim.conf`, optional `ufw` rule, `/etc/hosts` entry.
* **03_deploy_cluster.sh** – generates the kind config (host port → NodePort),
  creates the cluster, renders and applies `k8s/*.yaml`, waits for rollout.
* **04_validate.sh** – checks Docker, kubectl, cluster, nodes, deployment and
  HTTP endpoint; exits non-zero on any failure.
* **python/healthcheck.py** – dependency-free HTTP probe (exit 0 healthy,
  1 unhealthy).
* **k8s/** – namespace, ConfigMap (landing page), nginx Deployment (2 replicas,
  resource limits, probes) and NodePort Service.

## 8. Limitations / next steps

* Step 01 supports apt-based distributions; the Ansible playbook is a base
  for extending to other OS families.
* The sample workload is nginx standing in for the simulation services; replace
  `k8s/20_deployment.yaml` with the real images.
* Possible extensions: Ingress, Helm charts, CI pipeline running `--dry-run`
  and ShellCheck.
