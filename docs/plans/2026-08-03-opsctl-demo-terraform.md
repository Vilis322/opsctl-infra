# OpsCtl Demo — Terraform Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision a single Hetzner Cloud CAX21 (ARM) VPS via Terraform and hand its IP off to the existing Ansible `demo-vps` role so the OpsCtl demo comes back online.

**Architecture:** A new `opsctl-infra/terraform/` module (moved from the `~/Downloads/files/` skeleton) declares the ssh key, firewall, private network+subnet, and the CAX21 server (private net attached via an inline `network {}` block). `terraform apply` outputs the public IPv4, which is exported as `DEMO_VPS_IP` for the pre-existing Ansible playbook.

**Tech Stack:** Terraform (hcloud provider ≥1.45), Hetzner Cloud, Ansible, Ubuntu 24.04 arm64.

## Global Constraints

- Provider: `hetznercloud/hcloud >= 1.45`; Terraform `>= 1.6`.
- Server: `cax21`, `ubuntu-24.04`, location `hel1` (defaults; overridable via tfvars).
- **IPv4 stays enabled** (`ipv4_enabled = true`). Never go IPv6-only — GitHub Actions runners have no IPv6 and would break the CI/CD deploy.
- Private network attached via **inline `network {}` block only**. Never add a separate `hcloud_server_network` resource for this server (conflict).
- SSH key = `~/.ssh/id_ed25519_demo` (Terraform uploads `id_ed25519_demo.pub`; Ansible authenticates with the private half). The keypair already exists.
- `ssh_allowed_ips = ["0.0.0.0/0", "::/0"]` (key-only auth). Not locked to a single IP (user's IP roams).
- **Secrets:** the Hetzner token is NEVER written literally into a command or a committed file. It lives in `~/.hcloud-token` (chmod 600, outside the repo) and is read inline via `$(cat ~/.hcloud-token)`.
- State is local `terraform.tfstate`, git-ignored. No remote backend.
- `terraform apply` creates billable infrastructure — it is an explicit user-approval checkpoint, never run unattended.

---

### Task 1: Land the Terraform module in the repo

**Files:**
- Create: `opsctl-infra/terraform/versions.tf` (copy of skeleton)
- Create: `opsctl-infra/terraform/main.tf` (copy of skeleton)
- Create: `opsctl-infra/terraform/outputs.tf` (copy of skeleton)
- Create: `opsctl-infra/terraform/terraform.tfvars.example` (copy of skeleton)
- Create: `opsctl-infra/terraform/variables.tf` (copy + one edit)
- Create: `opsctl-infra/terraform/.gitignore` (merged, hardened)

**Interfaces:**
- Produces: a `terraform/` module whose `variables.tf` defaults to `ssh_public_key_path = "~/.ssh/id_ed25519_demo.pub"`; outputs `server_ipv4`, `server_ipv6`, `server_private_ip`, `server_status`.

- [ ] **Step 1: Copy the four unchanged skeleton files**

```bash
mkdir -p ~/Projects/saas/opsctl-infra/terraform
cd ~/Projects/saas/opsctl-infra/terraform
cp ~/Downloads/files/versions.tf ~/Downloads/files/main.tf \
   ~/Downloads/files/outputs.tf ~/Downloads/files/terraform.tfvars.example .
cp ~/Downloads/files/variables.tf .
```

- [ ] **Step 2: Fix the SSH key default in `variables.tf`**

Change the `ssh_public_key_path` default so Terraform uploads the same key Ansible uses:

```hcl
variable "ssh_public_key_path" {
  description = "Path to your LOCAL public SSH key (the .pub). Private key stays on your machine."
  type        = string
  default     = "~/.ssh/id_ed25519_demo.pub"
}
```

- [ ] **Step 3: Write a single hardened `.gitignore`**

The skeleton shipped two files (`.gitignore` + `gitignore`); write one:

```gitignore
# Terraform
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Secrets — never commit the real tfvars
terraform.tfvars
*.auto.tfvars
```

- [ ] **Step 4: Verify no other file references the old key path or a separate network resource**

Run:
```bash
cd ~/Projects/saas/opsctl-infra/terraform
grep -n "id_ed25519" variables.tf                 # expect: id_ed25519_demo.pub
grep -c "hcloud_server_network" *.tf              # expect: 0
grep -n "ipv4_enabled" main.tf                    # expect: true
```
Expected: key path is the demo key; zero `hcloud_server_network` resources; IPv4 enabled.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/saas/opsctl-infra
git add terraform/
git commit -m "feat: add Terraform module for Hetzner CAX21 demo VPS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Static validation (no token, no cost)

**Files:** none (validation only).

**Interfaces:**
- Consumes: the `terraform/` module from Task 1.
- Produces: a `.terraform/` provider install and a green `terraform validate`.

- [ ] **Step 1: Init the provider**

Run:
```bash
cd ~/Projects/saas/opsctl-infra/terraform
terraform init
```
Expected: "Terraform has been successfully initialized!" and hcloud provider ≥1.45 installed.

- [ ] **Step 2: Format check**

Run:
```bash
terraform fmt -check -diff
```
Expected: no diff (skeleton is already formatted). If it reports changes, run `terraform fmt` and re-commit.

- [ ] **Step 3: Validate**

Run:
```bash
terraform validate
```
Expected: "Success! The configuration is valid." — this catches syntax/reference errors WITHOUT contacting Hetzner or spending money.

- [ ] **Step 4: Commit the lockfile only**

```bash
cd ~/Projects/saas/opsctl-infra
git add terraform/.terraform.lock.hcl
git commit -m "chore: pin hcloud provider lockfile

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Store the token and run `terraform plan`

**Files:**
- Create: `~/.hcloud-token` (outside the repo, chmod 600) — user pastes the token here.

**Interfaces:**
- Consumes: the validated module; the Hetzner Read & Write token.
- Produces: a reviewed `terraform plan` showing exactly the resources to be created (ssh key, firewall, network, subnet, server) — nothing destroyed.

- [ ] **Step 1: User stores the token in `~/.hcloud-token`**

The user runs this themselves so the token is never in the agent transcript:
```
! printf '%s' 'PASTE_TOKEN_HERE' > ~/.hcloud-token && chmod 600 ~/.hcloud-token
```

- [ ] **Step 2: Confirm the token file is present and private**

Run:
```bash
ls -l ~/.hcloud-token   # expect: -rw------- (600)
test -s ~/.hcloud-token && echo "token present" || echo "EMPTY — stop"
```
Expected: mode `600`, non-empty.

- [ ] **Step 3: Run plan with the token read inline**

Run:
```bash
cd ~/Projects/saas/opsctl-infra/terraform
TF_VAR_hcloud_token="$(cat ~/.hcloud-token)" terraform plan -out=tfplan
```
Expected: `Plan: 5 to add, 0 to change, 0 to destroy.` (hcloud_ssh_key, hcloud_firewall, hcloud_network, hcloud_network_subnet, hcloud_server). If the token is bad you'll get a 401 here — cheap to fix, nothing created yet.

- [ ] **Step 4: Review the plan output together with the user**

Confirm: server_type `cax21`, image `ubuntu-24.04`, location `hel1`, `ipv4_enabled = true`, inline `network` block present, no `hcloud_server_network`. STOP and get explicit user approval before Task 4.

---

### Task 4: Apply — create the VPS (billable, user-approved)

**Files:** creates `terraform.tfstate` (git-ignored).

**Interfaces:**
- Consumes: the approved `tfplan` from Task 3.
- Produces: a running CAX21 server; `terraform output -raw server_ipv4` returns its public IP.

- [ ] **Step 1: Apply the saved plan (explicit user go required)**

Only after the user says "go":
```bash
cd ~/Projects/saas/opsctl-infra/terraform
TF_VAR_hcloud_token="$(cat ~/.hcloud-token)" terraform apply tfplan
```
Expected: `Apply complete! Resources: 5 added, 0 changed, 0 destroyed.`

- [ ] **Step 2: Read the outputs**

Run:
```bash
terraform output
terraform output -raw server_ipv4
```
Expected: a public IPv4, an IPv6, private IP `10.0.1.10`, status `running`.

- [ ] **Step 3: Verify SSH reachability with the demo key**

Run (wait ~20–30s after apply for cloud-init/boot):
```bash
IP=$(terraform output -raw server_ipv4)
ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_demo root@"$IP" 'hostnamectl; uname -m'
```
Expected: logs in without a password prompt; `Architecture: arm64` / `aarch64` confirms the CAX box.

---

### Task 5: Terraform → Ansible handoff helper

**Files:**
- Create: `opsctl-infra/scripts/tf-to-ansible.sh`

**Interfaces:**
- Consumes: `terraform output -raw server_ipv4`.
- Produces: prints/exports `DEMO_VPS_IP` for the Ansible inventory (`ansible/inventory/hosts.yml` reads `lookup('env', 'DEMO_VPS_IP')`).

- [ ] **Step 1: Write the helper**

```bash
#!/usr/bin/env bash
# Reads the Terraform server IP and prints an export line for Ansible.
# Usage:  eval "$(scripts/tf-to-ansible.sh)"  then run ansible-playbook.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IP="$(terraform -chdir="$REPO_ROOT/terraform" output -raw server_ipv4)"

if [[ -z "$IP" ]]; then
  echo "error: empty server_ipv4 — did terraform apply run?" >&2
  exit 1
fi

echo "export DEMO_VPS_IP=$IP"
```

- [ ] **Step 2: Make it executable and smoke-test it**

Run:
```bash
cd ~/Projects/saas/opsctl-infra
chmod +x scripts/tf-to-ansible.sh
./scripts/tf-to-ansible.sh          # expect: export DEMO_VPS_IP=<the IP>
eval "$(./scripts/tf-to-ansible.sh)" && echo "DEMO_VPS_IP=$DEMO_VPS_IP"
```
Expected: prints the export line; `DEMO_VPS_IP` is set to the real IP.

- [ ] **Step 3: Commit**

```bash
git add scripts/tf-to-ansible.sh
git commit -m "feat: add Terraform-to-Ansible IP handoff helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Provision the box with Ansible

**Files:** none (uses existing `ansible/` role).

**Interfaces:**
- Consumes: `DEMO_VPS_IP` from Task 5; the demo private key.
- Produces: a fully provisioned demo VPS (Node 20, PostgreSQL 16, Redis 7, nginx, PM2, key-only SSH).

- [ ] **Step 1: Connectivity check via Ansible**

Run:
```bash
cd ~/Projects/saas/opsctl-infra
eval "$(./scripts/tf-to-ansible.sh)"
cd ansible && ansible -i inventory/hosts.yml demo -m ping
```
Expected: `demo-vps | SUCCESS => "ping": "pong"`.

- [ ] **Step 2: Dry-run the playbook (--check)**

Run:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/setup-demo-vps.yml --check --diff
```
Expected: completes without unreachable/failed hosts; shows the changes it would make. (Some `--check` steps may skip if they depend on earlier ones; note but don't block.)

- [ ] **Step 3: Run the playbook for real**

Run:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/setup-demo-vps.yml
```
Expected: `failed=0`, `unreachable=0` in the play recap.

- [ ] **Step 4: Verify services are up on the box**

Run:
```bash
ssh -i ~/.ssh/id_ed25519_demo root@"$DEMO_VPS_IP" \
  'node -v; psql --version; redis-cli --version; nginx -v; pm2 -v; pm2 ls'
```
Expected: Node 20.x, PostgreSQL 16, Redis 7, nginx, PM2 installed; `pm2 ls` shows the demo processes (or an empty list if apps deploy via CI/CD separately).

---

### Task 7: Infrastructure walkthrough (documentation for the user)

**Files:** none (explanatory session; optionally capture notes in `opsctl-infra/README.md` if gaps are found).

**Interfaces:**
- Consumes: the now-running stack.
- Produces: the user understands what each piece does.

- [ ] **Step 1: Walk the Terraform module** — `versions.tf`, `variables.tf`, `main.tf` (ssh key → firewall → network/subnet → server + inline network block + public_net), `outputs.tf`. Explain what each resource is and why.

- [ ] **Step 2: Walk the Ansible layer** — `ansible.cfg`, `inventory/hosts.yml` (the `DEMO_VPS_IP` env lookup), `playbooks/setup-demo-vps.yml`, and the `demo-vps` role (`tasks/main.yml` 10 steps, `create_db.yml`, `issue_ssl.yml`, templates, vars, handlers).

- [ ] **Step 3: Walk the monitoring stack** — `monitoring/docker-compose.yml` (Prometheus/Grafana/Loki/Promtail), ports, provisioning.

- [ ] **Step 4: Walk the scripts and CI/CD** — the `setup-*-demo-envs.sh` GitHub environment scripts and how the GitHub Actions → SSH deploy flow uses them; map each service to its port/database.

---

## Self-Review

**Spec coverage:** placement (T1) ✓, IPv4-stays (Global + T1/T3) ✓, inline-network-only (Global + T1 grep) ✓, ssh key alignment (T1) ✓, firewall open key-only (T1, unchanged skeleton) ✓, local state (Global, T4) ✓, minimal skeleton edits (T1) ✓, TF→Ansible handoff (T5/T6) ✓, YAGNI out-of-scope untouched ✓, follow-up walkthrough (T7) ✓. No gaps.

**Placeholder scan:** the only literal placeholder is `PASTE_TOKEN_HERE`, which is intentional and user-supplied (a secret the agent must not know). No TBD/TODO/"handle edge cases" left.

**Type/name consistency:** output name `server_ipv4` used identically in T4/T5/T6; env var `DEMO_VPS_IP` matches the inventory lookup; key path `~/.ssh/id_ed25519_demo(.pub)` consistent across Terraform var and Ansible; token file `~/.hcloud-token` consistent across T3/T4.
