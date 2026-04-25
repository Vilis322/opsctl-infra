#!/bin/bash
# Setup GitHub environment secrets for DomCtl demo-prod and demo-stage
# Usage: SSH_KEY_FILE=~/.ssh/id_ed25519_demo ANTHROPIC_API_KEY=sk-... ./setup-domctl-demo-envs.sh

set -euo pipefail

REPO="Vilis322/domctl"

# === Validate required inputs ===
if [[ -z "${SSH_KEY_FILE:-}" ]]; then
  echo "ERROR: SSH_KEY_FILE not set. Usage:"
  echo "  SSH_KEY_FILE=~/.ssh/id_ed25519_demo ANTHROPIC_API_KEY=sk-... $0"
  exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "ERROR: SSH key file not found: $SSH_KEY_FILE"
  exit 1
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY not set"
  exit 1
fi

SPACESHIP_PROXY="${SPACESHIP_PROXY:-}"

echo "=== Deleting old environments ==="

for OLD_ENV in demo; do
  echo "Deleting: $OLD_ENV"
  gh api --method DELETE "repos/$REPO/environments/$OLD_ENV" --silent 2>/dev/null || echo "  (not found, skipping)"
done

echo ""
echo "=== Creating environments ==="

for ENV in demo-prod demo-stage; do
  echo "Creating environment: $ENV"
  gh api --method PUT "repos/$REPO/environments/$ENV" --silent
done

echo ""
echo "=== Setting demo-prod secrets ==="

gh secret set SSH_HOST        -b "${DEMO_VPS_IP}"                                                               -e demo-prod -R "$REPO"
gh secret set SSH_USER        -b "root"                                                                        -e demo-prod -R "$REPO"
gh secret set SSH_KEY         < "$SSH_KEY_FILE"                                                                -e demo-prod -R "$REPO"
gh secret set SSH_PORT        -b "22"                                                                          -e demo-prod -R "$REPO"
gh secret set DB_HOST         -b "localhost"                                                                    -e demo-prod -R "$REPO"
gh secret set DB_PORT         -b "5432"                                                                        -e demo-prod -R "$REPO"
gh secret set DB_USER         -b "domctl_demo"                                                                 -e demo-prod -R "$REPO"
gh secret set DB_NAME         -b "domctl_demo"                                                                 -e demo-prod -R "$REPO"
gh secret set DB_PASSWORD     -b "${DOMCTL_DEMO_DB_PASSWORD}"                                            -e demo-prod -R "$REPO"
gh secret set SESSION_SECRET  -b "${GENERATED_SECRET}"             -e demo-prod -R "$REPO"
gh secret set ENCRYPTION_KEY  -b "${GENERATED_SECRET}"             -e demo-prod -R "$REPO"
gh secret set JWT_SECRET      -b "${GENERATED_SECRET}"             -e demo-prod -R "$REPO"
gh secret set JWT_REFRESH_SECRET -b "${GENERATED_SECRET}"          -e demo-prod -R "$REPO"
gh secret set REDIS_URL       -b "redis://localhost:6379/0"                                                    -e demo-prod -R "$REPO"
gh secret set ANTHROPIC_API_KEY -b "$ANTHROPIC_API_KEY"                                                        -e demo-prod -R "$REPO"
gh secret set SPACESHIP_PROXY -b "$SPACESHIP_PROXY"                                                            -e demo-prod -R "$REPO"

echo ""
echo "=== Setting demo-prod variables ==="

gh variable set APP_DIR             -b "/var/www/domctl-demo"       -e demo-prod -R "$REPO"
gh variable set PM2_NAME            -b "domctl_demo"                -e demo-prod -R "$REPO"
gh variable set DOMAIN              -b "domctl.opsctl.tech"         -e demo-prod -R "$REPO"
gh variable set PORT                -b "3001"                       -e demo-prod -R "$REPO"
gh variable set JWT_ACCESS_EXPIRY   -b "2h"                        -e demo-prod -R "$REPO"
gh variable set JWT_REFRESH_EXPIRY  -b "24h"                       -e demo-prod -R "$REPO"

echo ""
echo "=== Setting demo-stage secrets ==="

gh secret set SSH_HOST        -b "${DEMO_VPS_IP}"                                                               -e demo-stage -R "$REPO"
gh secret set SSH_USER        -b "root"                                                                        -e demo-stage -R "$REPO"
gh secret set SSH_KEY         < "$SSH_KEY_FILE"                                                                -e demo-stage -R "$REPO"
gh secret set SSH_PORT        -b "22"                                                                          -e demo-stage -R "$REPO"
gh secret set DB_HOST         -b "localhost"                                                                    -e demo-stage -R "$REPO"
gh secret set DB_PORT         -b "5432"                                                                        -e demo-stage -R "$REPO"
gh secret set DB_USER         -b "domctl_demo_stage"                                                           -e demo-stage -R "$REPO"
gh secret set DB_NAME         -b "domctl_demo_stage"                                                           -e demo-stage -R "$REPO"
gh secret set DB_PASSWORD     -b "${DOMCTL_STAGE_DB_PASSWORD}"                                            -e demo-stage -R "$REPO"
gh secret set SESSION_SECRET  -b "${GENERATED_SECRET}"             -e demo-stage -R "$REPO"
gh secret set ENCRYPTION_KEY  -b "${GENERATED_SECRET}"             -e demo-stage -R "$REPO"
gh secret set JWT_SECRET      -b "${GENERATED_SECRET}"             -e demo-stage -R "$REPO"
gh secret set JWT_REFRESH_SECRET -b "${GENERATED_SECRET}"          -e demo-stage -R "$REPO"
gh secret set REDIS_URL       -b "redis://localhost:6379/1"                                                    -e demo-stage -R "$REPO"
gh secret set ANTHROPIC_API_KEY -b "$ANTHROPIC_API_KEY"                                                        -e demo-stage -R "$REPO"
gh secret set SPACESHIP_PROXY -b "$SPACESHIP_PROXY"                                                            -e demo-stage -R "$REPO"

echo ""
echo "=== Setting demo-stage variables ==="

gh variable set APP_DIR             -b "/var/www/domctl-demo-stage" -e demo-stage -R "$REPO"
gh variable set PM2_NAME            -b "domctl_demo_stage"          -e demo-stage -R "$REPO"
gh variable set DOMAIN              -b "domctl.dev"                 -e demo-stage -R "$REPO"
gh variable set PORT                -b "3002"                       -e demo-stage -R "$REPO"
gh variable set JWT_ACCESS_EXPIRY   -b "2h"                        -e demo-stage -R "$REPO"
gh variable set JWT_REFRESH_EXPIRY  -b "24h"                       -e demo-stage -R "$REPO"

echo ""
echo "=== Done! Verifying ==="
echo ""
echo "Environments:"
gh api "repos/$REPO/environments" --jq '.environments[].name'
echo ""
echo "demo-prod secrets:"
gh secret list -e demo-prod -R "$REPO"
echo ""
echo "demo-prod variables:"
gh variable list -e demo-prod -R "$REPO"
echo ""
echo "demo-stage secrets:"
gh secret list -e demo-stage -R "$REPO"
echo ""
echo "demo-stage variables:"
gh variable list -e demo-stage -R "$REPO"
