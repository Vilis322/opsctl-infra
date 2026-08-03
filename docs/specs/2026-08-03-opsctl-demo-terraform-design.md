# OpsCtl Demo — Terraform Provisioning Design

**Date:** 2026-08-03
**Status:** Approved
**Author:** Kyrylo Pryiomyshev (with Claude Code)

## Goal

Bring the OpsCtl demo back online: provision a single Hetzner Cloud ARM VPS
(CAX21) via Terraform, then hand off to the existing Ansible role
(`demo-vps`) that installs Node/PostgreSQL/Redis/nginx/PM2 and deploys the
demo services. Terraform is the missing layer — the Ansible side already
exists in `opsctl-infra/ansible/`.

## Context

- Hetzner Cloud account created, verified, Read & Write API token obtained.
- A working Terraform skeleton for hcloud/CAX21 exists in `~/Downloads/files/`.
- Ansible inventory (`ansible/inventory/hosts.yml`) already expects:
  - `ansible_host` from env var `DEMO_VPS_IP`
  - `ansible_user: root`
  - key `~/.ssh/id_ed25519_demo`
- The demo SSH keypair `~/.ssh/id_ed25519_demo(.pub)` already exists locally.

## Decisions

### Placement
Move the Terraform skeleton into the existing repo at
`opsctl-infra/terraform/` (alongside `ansible/`, `monitoring/`, `scripts/`).
All IaC in one repo, under git.

### Networking — IPv4 stays enabled
Keep `ipv4_enabled = true` (skeleton default). **Do NOT** go IPv6-only to
save €0.60/mo. Reason: the demo deploys via GitHub Actions → SSH to the VPS,
and GitHub-hosted runners have no IPv6, so an IPv6-only host would break the
CI/CD deploy. Own SSH from mobile/hotel networks is also often v4-only.
IPv6 stays enabled too (free).

### Private network — inline block only
The private network is attached via the **inline `network {}` block inside
`hcloud_server`** (main.tf lines 76-79). Do NOT add a separate
`hcloud_server_network` resource for the same server — the two approaches
conflict. Keep the inline block; leave `hcloud_network` +
`hcloud_network_subnet` as the network/subnet definitions.

### SSH key alignment
Terraform must upload the SAME key Ansible uses. Set
`variables.tf` default `ssh_public_key_path` → `~/.ssh/id_ed25519_demo.pub`
(was `~/.ssh/id_ed25519.pub`). The keypair already exists — nothing to
generate.

### Firewall / SSH access
Keep `ssh_allowed_ips = ["0.0.0.0/0", "::/0"]` (skeleton default). User's IP
changes (home/travel); locking to a single IP would risk self-lockout. Port
22 is open but access is key-only (Ansible disables password auth). Ports
80/443/icmp open to all, as in the skeleton.

### State
Local `terraform.tfstate`, git-ignored. No remote backend — YAGNI for a
single-operator demo. Revisit (Hetzner Object Storage / TF Cloud) only if a
real need appears.

## Changes to the skeleton (minimal)

1. `variables.tf`: `ssh_public_key_path` default → `~/.ssh/id_ed25519_demo.pub`.
2. `.gitignore`: merge the skeleton's two files (`.gitignore` + `gitignore`)
   into one; ensure it ignores `*.tfstate*`, `.terraform/`, `terraform.tfvars`.
3. `main.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example`: copied
   as-is (no structural change).

## Terraform → Ansible handoff

Ansible reads `DEMO_VPS_IP` from the environment. After `apply`:

```bash
export DEMO_VPS_IP=$(terraform -chdir=terraform output -raw server_ipv4)
cd ansible && ansible-playbook playbooks/setup-demo-vps.yml
```

Add a small helper `scripts/tf-to-ansible.sh` that reads the Terraform output
and exports/prints `DEMO_VPS_IP` so the step isn't copy-pasted by hand.

## Out of scope (YAGNI)

- cloud-init / k3s bootstrap (skeleton keeps this commented out).
- Remote Terraform state backend.
- Multi-node / k3s agents (private network is provisioned as a foundation
  only).

## Follow-up (separate step, after successful apply + Ansible run)

Full infrastructure walkthrough for the user: go file-by-file through
Terraform, the Ansible `demo-vps` role and playbooks, the monitoring stack,
and the deploy scripts — explaining what each piece does, how they connect,
which service runs on which port, and how the CI/CD deploy works.

## Success criteria

- `terraform -chdir=terraform init && plan` runs clean against the real token.
- `terraform apply` creates the CAX21 server, firewall, network, ssh key.
- `terraform output -raw server_ipv4` returns a reachable IP.
- SSH in with `id_ed25519_demo` works.
- The Ansible playbook runs against `DEMO_VPS_IP` and provisions the box.
