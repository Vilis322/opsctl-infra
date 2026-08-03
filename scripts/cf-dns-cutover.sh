#!/usr/bin/env bash
# Cloudflare DNS cutover — repoint demo A records from an old IP to a new one.
#
# Finds every A record in the given zones whose content == OLD_IP and rewrites
# it to NEW_IP, preserving the proxied flag and TTL. Dry-run by default;
# pass --apply to actually change records.
#
# Token: read from ~/.cloudflare-token (chmod 600). Never pass it on the CLI.
#   Needs a token with Zone.DNS:Edit on the target zones.
#
# Usage:
#   scripts/cf-dns-cutover.sh <OLD_IP> [NEW_IP] [--apply] [--zones "a.tech b.dev"]
#                             [--only "fqdn1,fqdn2"]
#   # NEW_IP defaults to `terraform -chdir=terraform output -raw server_ipv4`
#   # --only restricts changes to the listed FQDNs (default: all records on OLD_IP)
#
# Examples:
#   scripts/cf-dns-cutover.sh 64.111.93.210                 # dry-run, new IP from TF
#   scripts/cf-dns-cutover.sh 64.111.93.210 1.2.3.4 --apply # apply explicit IP
set -euo pipefail

TOKEN_FILE="${CF_TOKEN_FILE:-$HOME/.cloudflare-token}"
ZONES_DEFAULT="opsctl.tech"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- args ---------------------------------------------------------------
OLD_IP="${1:-}"; shift || true
NEW_IP=""
APPLY=0
ZONES="$ZONES_DEFAULT"
ONLY=""   # optional comma-separated FQDN allowlist; empty = all matching records
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --zones) ZONES="$2"; shift ;;
    --only)  ONLY="$2"; shift ;;
    *) NEW_IP="$1" ;;
  esac
  shift
done

[[ -n "$OLD_IP" ]] || { echo "usage: $0 <OLD_IP> [NEW_IP] [--apply] [--zones \"z1 z2\"]" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
[[ -s "$TOKEN_FILE" ]] || { echo "error: token file $TOKEN_FILE missing/empty" >&2; exit 1; }
TOKEN="$(cat "$TOKEN_FILE")"

# NEW_IP falls back to the Terraform output
if [[ -z "$NEW_IP" ]]; then
  NEW_IP="$(terraform -chdir="$REPO_ROOT/terraform" output -raw server_ipv4 2>/dev/null || true)"
fi
[[ -n "$NEW_IP" ]] || { echo "error: NEW_IP not given and not readable from terraform output" >&2; exit 1; }

echo "OLD_IP=$OLD_IP  ->  NEW_IP=$NEW_IP   zones: $ZONES   mode: $([[ $APPLY -eq 1 ]] && echo APPLY || echo DRY-RUN)"
echo

cf() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }
API="https://api.cloudflare.com/client/v4"

changed=0
for zone in $ZONES; do
  zid="$(cf "$API/zones?name=$zone" | jq -r '.result[0].id // empty')"
  if [[ -z "$zid" ]]; then
    echo "!! zone $zone not found or token lacks access — skipping" >&2
    continue
  fi
  # A records in this zone pointing at OLD_IP
  records="$(cf "$API/zones/$zid/dns_records?type=A&content=$OLD_IP&per_page=100" \
             | jq -c '.result[]')"
  if [[ -z "$records" ]]; then
    echo "[$zone] no A records point at $OLD_IP"
    continue
  fi
  while IFS= read -r rec; do
    name="$(jq -r '.name' <<<"$rec")"
    rid="$(jq -r '.id' <<<"$rec")"
    proxied="$(jq -r '.proxied' <<<"$rec")"
    ttl="$(jq -r '.ttl' <<<"$rec")"
    if [[ -n "$ONLY" && ",$ONLY," != *",$name,"* ]]; then
      echo "[$zone] $name  — skipped (not in --only list)"
      continue
    fi
    echo "[$zone] $name  $OLD_IP -> $NEW_IP  (proxied=$proxied)"
    if [[ $APPLY -eq 1 ]]; then
      body="$(jq -n --arg n "$name" --arg c "$NEW_IP" --argjson p "$proxied" --argjson t "$ttl" \
              '{type:"A",name:$n,content:$c,proxied:$p,ttl:$t}')"
      ok="$(cf -X PUT "$API/zones/$zid/dns_records/$rid" --data "$body" | jq -r '.success')"
      [[ "$ok" == "true" ]] && echo "    updated" || { echo "    FAILED" >&2; }
    fi
    changed=$((changed+1))
  done <<<"$records"
done

echo
if [[ $APPLY -eq 1 ]]; then
  echo "done — $changed record(s) updated. DNS/CF cache may take a few minutes."
else
  echo "dry-run — $changed record(s) would change. Re-run with --apply to commit."
fi
