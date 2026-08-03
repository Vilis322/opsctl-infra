#!/usr/bin/env bash
# Reads the Terraform server IP and prints an export line for Ansible.
# Ansible's inventory (inventory/hosts.yml) reads ansible_host from
# the DEMO_VPS_IP environment variable.
#
# Usage:  eval "$(scripts/tf-to-ansible.sh)"   then run ansible-playbook.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IP="$(terraform -chdir="$REPO_ROOT/terraform" output -raw server_ipv4)"

if [[ -z "$IP" ]]; then
  echo "error: empty server_ipv4 — did terraform apply run?" >&2
  exit 1
fi

echo "export DEMO_VPS_IP=$IP"
