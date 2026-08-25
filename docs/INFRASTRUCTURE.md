# OpsCtl — Infrastructure Architecture

How the OpsCtl demo ecosystem is provisioned and served. This document describes
**what** the infrastructure is and **why** it is built this way. For step-by-step
operational commands see the "Lifecycle" section at the end.

## Overview

The whole demo ecosystem runs on **one Hetzner Cloud VPS**. Infrastructure is
defined as code in two layers with a clean separation of concerns:

| Layer | Tool | Answers | Lives in |
|---|---|---|---|
| **Provisioning** | Terraform | "What machine exists?" (server, network, firewall, SSH key) | `terraform/` |
| **Configuration** | Ansible | "What is installed and configured on it?" (nginx, PostgreSQL, Redis, Node, PM2, TLS) | `ansible/` |
| **Deployment** | GitHub Actions | "What application code is running?" (per-service CI/CD) | each service repo |

Terraform creates the empty box and prints its IP. Ansible takes that IP and turns
the box into a working web host. GitHub Actions then ships each app onto it. The
three layers never overlap: Ansible never deploys app code, GitHub Actions never
touches server config.

```
Terraform  ──creates──►  Hetzner VPS (IP)
                              │
Ansible    ──configures──►  nginx · PostgreSQL · Redis · Node/PM2 · TLS certs
                              │
GH Actions ──deploys────►  domctl · financecrm · worknest  (code + pm2 restart)
```

## Layer 1 — Terraform (the server)

Terraform talks to the **Hetzner Cloud API** and declares a small set of resources:

- **`hcloud_ssh_key`** — uploads the local public key (`~/.ssh/id_ed25519_demo.pub`)
  so the server trusts it at boot. The private key never leaves the laptop.
- **`hcloud_firewall`** — inbound rules: SSH (22), HTTP (80), HTTPS (443), ICMP.
  SSH source is a variable (`ssh_allowed_ips`, default open — key-only auth).
- **`hcloud_network` + `hcloud_network_subnet`** — a private `10.0.0.0/16` network.
  Not strictly needed for one node, but it is the foundation for adding more nodes
  later without re-architecting.
- **`hcloud_server`** — the box itself. The private network is attached via an
  **inline `network {}` block** inside the server (intentionally — a separate
  `hcloud_server_network` resource would conflict with it).

**Outputs** expose the server's public IPv4/IPv6 and private IP so the next layer
can consume them (`terraform output -raw server_ipv4`).

Current server: **Hetzner `cx33`** (4 vCPU / 8 GB, x86, Ubuntu 24.04, `hel1`
Helsinki). ARM `cax21` was preferred but had no capacity in eu-central at build
time; the apps are architecture-agnostic, so x86 is fine.

**State** (`terraform.tfstate`) is Terraform's record of what it created. It is
gitignored (never committed) — it can contain sensitive values and is the source
of truth for the live infrastructure.

## Layer 2 — Ansible (the configuration)

Ansible connects over SSH (as `root`, using `id_ed25519_demo`) and makes the box
match a desired state. It is **idempotent**: safe to re-run — it only changes what
is out of sync.

The single role `demo-vps` does everything, driven by data in
`roles/demo-vps/vars/main.yml`. High-level steps (`tasks/main.yml`):

1. Install system packages: nginx, PostgreSQL 16, Redis 7, Node.js 20, PM2, certbot.
2. Ensure PostgreSQL listens on 5432 and Redis is running.
3. Clean up legacy PM2/Docker processes from the previous box.
4. Per service+environment: create a PostgreSQL database + user, and app directories.
5. Deploy **HTTP-only** nginx vhosts (so a cert can be issued).
6. Issue **Cloudflare Origin certificates** (see TLS below).
7. Upgrade vhosts to **HTTPS** where a cert now exists.
8. Configure the static apex dashboard vhost (`opsctl.tech`).
9. Validate nginx, disable SSH password auth, enable PM2 on boot.

### The service model (data-driven)

Everything is described declaratively in `vars/main.yml` as a list of `services`,
each with a list of `environments`. The tasks loop over the flattened
`service_envs` list — adding a service is a data edit, not new task code.

| Service | demo-prod domain | App port | nginx mode | PM2 |
|---|---|---|---|---|
| domctl | domctl.opsctl.tech | 3001 | proxy-all | cluster ×2 |
| financecrm | financecrm.opsctl.tech | 4001 | static SPA + `/api` proxy | cluster ×2 |
| worknest | worknest.opsctl.tech | 5001 (web) / 5011 (api) | split frontend/api | cluster ×2 |
| dashboard | opsctl.tech | — | static files only | — |

**Scope: demo-prod only.** The `vars` file still describes `demo-stage` (`*.dev`)
and a planned `ai` service, but those are **out of scope** and not provisioned —
runs are limited with `-e '{"deploy_envs":["demo-prod"]}'`.

### nginx: three serving modes (one template)

A single Jinja2 template (`nginx-site.conf.j2`) renders one of three shapes based
on which variables a service sets — this is why the apps have different frontends
but share one template:

- **proxy-all** (default) — everything proxied to one Node port. Used by domctl
  (Express serves both API and its own frontend). Includes SSE-friendly routes.
- **static SPA** (`frontend_dist` set) — nginx serves the built React `dist/`
  directly; only `/api` and `/socket.io` are proxied to Node. Used by financecrm.
- **split** (`api_port` set) — a frontend server on `app_port` and a separate API
  backend on `api_port`; `/api`, `/uploads`, `/socket.io` go to the API, `/` to
  the frontend. Used by worknest (Next.js web :5001 + API :5011).

## DNS & TLS

DNS is managed in **Cloudflare** (zone `opsctl.tech`). All demo A records are
proxied through Cloudflare (orange cloud).

TLS uses **Cloudflare Origin certificates** in **Full (strict)** mode:

- The Origin CA endpoint requires a CSR, so Ansible generates a key + CSR locally
  (`openssl`), POSTs the CSR to Cloudflare, and installs the returned cert
  (`/etc/ssl/cloudflare/<domain>.pem`) + local key on the server.
- Certs are valid 15 years and only trusted between Cloudflare and the origin —
  the browser sees Cloudflare's public cert. **Full (strict)** is required;
  Flexible causes a redirect loop because the origin also redirects HTTP→HTTPS.

> `tasks/issue_ssl.yml` (Let's Encrypt via certbot) is **legacy** — superseded by
> `issue_origin_cert.yml`. Kept for reference; not wired into the current flow.

## CI/CD boundary

- **Ansible** provisions the box only (services, dirs, nginx, certs). It never
  deploys application code.
- **GitHub Actions** (per service repo) builds and deploys code via SSH, then
  restarts PM2. Re-triggers must target **demo-prod only** — never stage.
- Prisma apps receive a full `DATABASE_URL` secret (not a bare password). Rotating
  a PostgreSQL password means updating that secret too.
- The apex **dashboard** `dist/` is seeded by a one-time manual `rsync` (an
  explicit, authorized exception to the CI/CD-only rule; automation is a TODO).

The `scripts/setup-<service>-demo-envs.sh` scripts create the GitHub Environment
secrets/variables each pipeline consumes (SSH creds, DB config, JWT secrets, ports).

## Monitoring

`monitoring/docker-compose.yml` defines a Prometheus + Grafana + Loki + Promtail
stack (metrics + log aggregation), served at `grafana.opsctl.tech`. See the root
`README.md` for the port table.

## Lifecycle (from zero to live)

```bash
# 1. Provision the server (Layer 1)
cd terraform
terraform init                 # download the hcloud provider
terraform plan                 # preview what will be created
terraform apply                # create the server; prints the IP

# 2. Hand the IP to Ansible
eval "$(../scripts/tf-to-ansible.sh)"   # exports DEMO_VPS_IP=<new ip>

# 3. Configure the box (Layer 2), demo-prod only, with TLS
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-demo-vps.yml \
  -e '{"deploy_envs":["demo-prod"]}' \
  -e "cf_api_token=$(cat ~/.cloudflare-token)"

# 4. Point DNS at the new server (dry-run first, then --apply)
../scripts/cf-dns-cutover.sh <OLD_IP>
../scripts/cf-dns-cutover.sh <OLD_IP> --apply

# 5. Deploy app code — via each service's GitHub Actions (demo-prod)
```

## Repository layout

```
opsctl-infra/
├── terraform/           # Layer 1 — the server (HCL)
│   ├── versions.tf      # required Terraform + hcloud provider versions
│   ├── variables.tf     # inputs (token, location, server_type, ssh key…)
│   ├── main.tf          # resources: ssh key, firewall, network, server
│   ├── outputs.tf       # exposes server IPs
│   └── terraform.tfvars.example   # template for the real (gitignored) tfvars
├── ansible/             # Layer 2 — the configuration (YAML)
│   ├── ansible.cfg      # inventory path, ssh options
│   ├── inventory/hosts.yml        # the one host; IP from $DEMO_VPS_IP
│   ├── playbooks/setup-demo-vps.yml
│   └── roles/demo-vps/
│       ├── vars/main.yml          # service/env data model
│       ├── tasks/                 # main, create_db, issue_origin_cert, dashboard
│       ├── templates/             # nginx vhosts (Jinja2)
│       └── handlers/main.yml      # restart/reload triggers
├── scripts/             # glue: tf→ansible, DNS cutover, GH env setup
└── monitoring/          # Prometheus + Grafana + Loki + Promtail (docker-compose)
```
