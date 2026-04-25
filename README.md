# OpsCtl Infrastructure

Infrastructure-as-Code for the OpsCtl ecosystem — Ansible playbooks, monitoring stack, and deployment scripts.

## Structure

```
opsctl-infra/
├── ansible/
│   ├── ansible.cfg                  # Ansible configuration
│   ├── inventory/hosts.yml          # Server inventory
│   ├── playbooks/
│   │   └── setup-demo-vps.yml      # Full demo VPS provisioning
│   └── roles/
│       └── demo-vps/
│           ├── tasks/main.yml       # 10-step provisioning (Node, PG, Redis, nginx, PM2)
│           ├── tasks/create_db.yml  # Per-service database creation
│           ├── tasks/issue_ssl.yml  # Let's Encrypt SSL
│           ├── templates/           # nginx config templates (HTTP + HTTPS)
│           ├── vars/main.yml        # Service ports, DB names, PM2 config
│           └── handlers/main.yml    # Service restart handlers
│
├── monitoring/
│   ├── docker-compose.yml           # Prometheus + Grafana + Loki + Promtail
│   ├── prometheus/prometheus.yml    # Scrape configs for all services
│   ├── grafana/provisioning/       # Auto-provisioned datasources
│   ├── loki/loki-config.yml        # Log aggregation config
│   └── promtail/promtail-config.yml # Log scraping from PM2 + service logs
│
└── scripts/
    ├── setup-domctl-demo-envs.sh    # GitHub environment secrets for DomCtl
    ├── setup-fincrm-demo-envs.sh    # GitHub environment secrets for FinanceCRM
    └── setup-worknest-demo-envs.sh  # GitHub environment secrets for WorkNest
```

## Demo VPS Provisioning

The Ansible playbook provisions a complete demo environment on a single VPS:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup-demo-vps.yml
```

**What it provisions:**
- Node.js 20 LTS + PM2
- PostgreSQL 16
- Redis 7
- Nginx with per-subdomain configs
- SSH key-only auth (password disabled)
- PM2 startup on boot

**Services and ports:**

| Service | Port | Database | PM2 Mode |
|---|---|---|---|
| DomCtl | :3001 | domctl | cluster (2) |
| FinanceCRM | :4001 | financecrm | cluster (2) |
| WorkNest | :5001 (frontend) / :5011 (backend) | worknest | cluster (2) + fork |
| AI Analytics | :7001 | ai | planned |

**Database architecture:**

| Database | Service | Description |
|---|---|---|
| domctl | DomCtl | Domains, registrants, AI-generated names, user credentials |
| financecrm | FinanceCRM | Users, roles, wallets, incomes, expenses, teams, audit logs |
| worknest | WorkNest | Tasks, departments, users, comments, attachments, history |
| ai | AI Analytics | ML models, predictions, embeddings (planned) |

Each service has isolated databases per environment (demo-prod, demo-stage).

## Monitoring Stack

Docker Compose stack for observability:

```bash
cd monitoring
docker compose up -d
```

| Service | Port | Purpose |
|---|---|---|
| Prometheus | 9090 | Metrics collection (15s scrape interval) |
| Grafana | 3100 | Dashboards and alerting |
| Loki | 3101 | Log aggregation |
| Promtail | — | Log scraping from PM2 and service logs |

**Grafana access:** `https://grafana.opsctl.tech` (admin/admin)

## GitHub Environment Scripts

Each script creates GitHub environment secrets and variables for a service:

```bash
SSH_KEY_FILE=~/.ssh/id_ed25519_demo ./scripts/setup-domctl-demo-envs.sh
```

Creates `demo-prod` and `demo-stage` environments with:
- SSH credentials (host, user, key, port)
- Database connection strings
- JWT secrets
- Redis URLs
- Application-specific variables (port, domain, PM2 name)

## Infrastructure Principles

- **Ansible-first:** Server operations via playbooks, not manual SSH
- **Zero-downtime:** PM2 cluster mode (2 instances) for all demo-prod services
- **Environment isolation:** Separate databases, Redis DBs, and ports per environment
- **CI/CD pipeline:** GitHub Actions with health check after each deploy
- **Secrets management:** GitHub Environment Secrets, never in code

## Author

Kyrylo Pryiomyshev — [GitHub](https://github.com/Vilis322)

## License

All rights reserved.
