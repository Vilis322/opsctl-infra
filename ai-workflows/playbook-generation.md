# AI-Assisted Playbook Generation

## Problem

Writing Ansible playbooks for infrastructure changes is repetitive but not trivial. A typical playbook — even for a straightforward task like adding a new nginx vhost or rotating credentials — takes 30-45 minutes when done from scratch: writing the YAML, getting idempotency right, adding handlers, testing locally, handling edge cases.

For OpsCtl (a personal multi-service platform with 3 services across 2 environments each), I write roughly 8-10 playbooks or playbook modifications per month. That's 5+ hours of mechanical work that follows predictable patterns but still requires attention to detail.

## Why This Is Hard for AI Alone

**What AI handles well:**
- Ansible YAML syntax and module parameters
- Idempotency patterns (`creates:`, `when:`, `register:`)
- Common sequences (install package → configure → restart service)
- Handler chains and notification order

**What AI cannot decide for you:**
- Which servers are sensitive (prod database vs staging app server)
- When to use `serial: 1` (rolling) vs all-at-once
- Which config values are environment-specific secrets vs safe defaults
- Tribal knowledge: "this service needs a 5-second sleep after reload because of connection draining"
- Whether a change needs a maintenance window or can go live immediately

The boundary is clear: AI generates the draft, a human decides if it's safe to run.

## The Prompt Template

```
I need an Ansible playbook for the following infrastructure change.

**Target environment:** [demo-prod / demo-stage / all]
**Target hosts:** [host group or pattern from inventory]
**Change description:** [what needs to happen, in plain English]

**Current state:** [what exists now — relevant packages, configs, services]
**Desired state:** [what should exist after the playbook runs]

**Constraints:**
- [e.g., zero-downtime required / can tolerate brief restart]
- [e.g., must work on Ubuntu 22.04+]
- [e.g., service X depends on service Y — order matters]

**Validation command:** [how to verify success after running]
**Rollback plan:** [what to do if it breaks]

**Reference examples from this repo:**
- See roles/demo-vps/tasks/main.yml for naming conventions
- See roles/demo-vps/vars/main.yml for variable structure
- Handlers go in roles/demo-vps/handlers/main.yml

Generate an idempotent playbook. Use `ansible.builtin` FQCNs.
Add comments explaining non-obvious decisions.
```

The "reference examples" section is critical — without it, Claude generates valid Ansible but with different naming conventions, variable patterns, and file organization than what already exists in the repo.

## Example: Real Use Case

### (a) Input — Plain English

> I need to install Promtail on the demo VPS to ship PM2 and per-service logs to the Loki instance running in Docker on the same host.
>
> PM2 logs are in /root/.pm2/logs/*.log. Each service also writes to /var/www/{service}-demo*/logs/*.log.
>
> Promtail should run as a systemd service, scrape both locations, and label logs with `service` and `env` tags. Loki is at http://localhost:3100.

### (b) Claude's Generated Draft

```yaml
---
- name: Install and configure Promtail
  hosts: demo
  become: yes

  vars:
    promtail_version: "2.9.4"
    loki_url: "http://localhost:3100/loki/api/v1/push"

  tasks:
    - name: Download Promtail binary
      get_url:
        url: "https://github.com/grafana/loki/releases/download/v{{ promtail_version }}/promtail-linux-amd64.zip"
        dest: /tmp/promtail.zip

    - name: Unzip Promtail
      unarchive:
        src: /tmp/promtail.zip
        dest: /usr/local/bin/
        remote_src: yes

    - name: Create Promtail config directory
      file:
        path: /etc/promtail
        state: directory

    - name: Deploy Promtail config
      template:
        src: promtail-config.yml.j2
        dest: /etc/promtail/config.yml
      notify: restart promtail

    - name: Create Promtail systemd unit
      copy:
        dest: /etc/systemd/system/promtail.service
        content: |
          [Unit]
          Description=Promtail
          After=network.target

          [Service]
          ExecStart=/usr/local/bin/promtail-linux-amd64 -config.file=/etc/promtail/config.yml
          Restart=always

          [Install]
          WantedBy=multi-user.target
      notify:
        - reload systemd
        - restart promtail

    - name: Ensure Promtail is running
      service:
        name: promtail
        state: started
        enabled: yes

  handlers:
    - name: reload systemd
      command: systemctl daemon-reload

    - name: restart promtail
      service:
        name: promtail
        state: restarted
```

### (c) What I Changed After Review

1. **Removed binary install approach.** Promtail already runs inside the Docker Compose stack in `monitoring/`. Installing a separate binary would create version drift. Replaced the entire playbook with a config-only change — Promtail is a container, it reads config from a mounted volume.

2. **Fixed log paths.** Claude used a generic glob pattern. The actual PM2 log path on this VPS is `/root/.pm2/logs/`, and service logs follow the pattern `/var/www/{service}-demo*/logs/*.log` — these needed to match real directory names, not placeholders.

3. **Added pipeline stages.** The draft had no log parsing. Added a regex stage to extract the PM2 process ID and service name from the log line format (`0|fincrm | [2024-01-15 ...]: message`), which is specific to how PM2 formats output.

4. **Dropped the systemd unit entirely.** Not needed — Promtail runs in Docker, managed by `docker compose`.

### (d) Final Result

Instead of a playbook, the change became a config file update:

```yaml
# monitoring/promtail/promtail-config.yml (excerpt)

scrape_configs:
  - job_name: pm2-logs
    static_configs:
      - targets: [localhost]
        labels:
          job: pm2
          __path__: /pm2-logs/*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<pm2_id>\d+)\|(?P<service>\w+)\s*\| (?P<message>.*)$'
      - labels:
          service:
          pm2_id:

  - job_name: service-logs
    static_configs:
      - targets: [localhost]
        labels:
          job: domctl
          service: domctl
          __path__: /var/www/domctl-demo*/logs/*.log
      - targets: [localhost]
        labels:
          job: financecrm
          service: financecrm
          __path__: /var/www/fincrm-demo*/logs/*.log
      # ... additional services
```

Then applied with: `docker compose restart promtail`.

**Key takeaway:** Claude's draft was structurally correct Ansible — but it solved the wrong problem. The human review caught that Promtail was already containerized, and the right change was a config edit, not a new playbook. This is exactly why the review step is non-negotiable.

## What I Deliberately Left Out

- **No autonomous deploy.** Claude generates text — it never runs `ansible-playbook` or `docker compose up` on its own. I review every line before execution.
- **No custom UI.** The workflow is terminal-based: Claude Code CLI in the same shell where I run Ansible. Adding a UI would add complexity without value for a single operator.
- **No dynamic inventory integration.** The prompt template uses static host references. For a 3-service platform this is fine; at scale you'd want to feed live inventory state into the prompt.
- **No automatic testing.** Generated playbooks are tested manually on demo-stage before demo-prod. Molecule or similar would be the next step if the platform grows.

## Iteration Notes

After several months of using this workflow:

1. **Multi-turn refinement beats the "perfect prompt."** Starting with a rough description and iterating ("now add a handler for nginx reload", "make this idempotent") produces better results than trying to specify everything upfront.

2. **Few-shot examples from my own repo are critical.** Without them, Claude generates valid Ansible but with different conventions — `snake_case` vs my `kebab-case` file names, different variable structures, unfamiliar directory layouts. Pointing it to existing files in the repo aligns the output immediately.

3. **Split multi-file changes into separate prompts.** Asking for "a playbook that also updates the nginx template and adds a new vars entry" produces worse output than three focused requests. Each file has its own context and constraints.

4. **State what exists, not just what you want.** "Install Redis" generates a generic playbook. "Redis 7 is already installed via apt, I need to add a second instance on port 6380 with a separate data directory" generates something I can actually use.

5. **The biggest time savings are on boilerplate, not logic.** AI saves 20 minutes of YAML typing but zero minutes of deciding deployment strategy. The thinking is still mine — the typing is not.
