#!/bin/bash
# Setup GitHub environment secrets for FinanceCRM demo-prod and demo-stage
# Usage: SSH_KEY_FILE=~/.ssh/id_ed25519_demo ./setup-fincrm-demo-envs.sh

set -euo pipefail

REPO="Vilis322/financecrm"

if [[ -z "${SSH_KEY_FILE:-}" ]]; then
  echo "ERROR: SSH_KEY_FILE not set"
  exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "ERROR: SSH key file not found: $SSH_KEY_FILE"
  exit 1
fi

echo "=== Deleting old environments ==="
for OLD_ENV in demo stage; do
  echo "Deleting: $OLD_ENV"
  gh api --method DELETE "repos/$REPO/environments/$OLD_ENV" --silent 2>/dev/null || echo "  (not found)"
done

echo ""
echo "=== Updating demo-prod variables (fix Ansible mismatch) ==="

gh variable set APP_DIR            -b "/var/www/fincrm-demo"                       -e demo-prod -R "$REPO"
gh variable set PM2_NAME           -b "fincrm_demo"                                -e demo-prod -R "$REPO"
gh variable set PORT               -b "4001"                                       -e demo-prod -R "$REPO"
gh variable set LOG_FILE_PATH      -b "/var/www/fincrm-demo/logs"                  -e demo-prod -R "$REPO"
# These are already correct:
# DOMAIN=financecrm.opsctl.tech, CORS_ORIGIN, VITE_API_URL, APP_TITLE

echo ""
echo "=== Setting demo-prod secrets ==="

gh secret set SSH_HOST             -b "${DEMO_VPS_IP}"                              -e demo-prod -R "$REPO"
gh secret set SSH_USER             -b "root"                                       -e demo-prod -R "$REPO"
gh secret set SSH_KEY              < "$SSH_KEY_FILE"                               -e demo-prod -R "$REPO"
gh secret set SSH_PORT             -b "22"                                         -e demo-prod -R "$REPO"
gh secret set DATABASE_URL         -b "postgresql://fincrm_demo:${FINCRM_DEMO_DB_PASSWORD}@localhost:5432/fincrm_demo"              -e demo-prod -R "$REPO"
gh secret set JWT_SECRET           -b "${GENERATED_SECRET}"    -e demo-prod -R "$REPO"
gh secret set JWT_REFRESH_SECRET   -b "${GENERATED_SECRET}"    -e demo-prod -R "$REPO"
gh secret set REDIS_URL            -b "redis://localhost:6379/2"                   -e demo-prod -R "$REPO"
gh secret set LEADS_API_KEY        -b "9bfa549fcdb26406caa97f6e72ad6174bd978ffb9afbb027"                    -e demo-prod -R "$REPO"

echo ""
echo "=== Updating demo-stage variables (fix Ansible mismatch) ==="

gh variable set APP_DIR            -b "/var/www/fincrm-demo-stage"                 -e demo-stage -R "$REPO"
gh variable set PM2_NAME           -b "fincrm_demo_stage"                          -e demo-stage -R "$REPO"
gh variable set LOG_FILE_PATH      -b "/var/www/fincrm-demo-stage/logs"            -e demo-stage -R "$REPO"
# PORT=4002 already correct
# DOMAIN, CORS_ORIGIN, VITE_API_URL, APP_TITLE already correct

echo ""
echo "=== Setting demo-stage secrets ==="

gh secret set SSH_HOST             -b "${DEMO_VPS_IP}"                              -e demo-stage -R "$REPO"
gh secret set SSH_USER             -b "root"                                       -e demo-stage -R "$REPO"
gh secret set SSH_KEY              < "$SSH_KEY_FILE"                               -e demo-stage -R "$REPO"
gh secret set SSH_PORT             -b "22"                                         -e demo-stage -R "$REPO"
gh secret set DATABASE_URL         -b "postgresql://fincrm_demo_stage:${FINCRM_STAGE_DB_PASSWORD}@localhost:5432/fincrm_demo_stage"              -e demo-stage -R "$REPO"
gh secret set JWT_SECRET           -b "${GENERATED_SECRET}"    -e demo-stage -R "$REPO"
gh secret set JWT_REFRESH_SECRET   -b "${GENERATED_SECRET}"    -e demo-stage -R "$REPO"
gh secret set REDIS_URL            -b "redis://localhost:6379/3"                   -e demo-stage -R "$REPO"
gh secret set LEADS_API_KEY        -b "91815f2c487b90855fea4f9552d3831d94dc016b335d124b"                    -e demo-stage -R "$REPO"

echo ""
echo "=== Done! Verifying ==="
echo ""
echo "demo-prod secrets:" && gh secret list -e demo-prod -R "$REPO"
echo "" && echo "demo-prod variables:" && gh variable list -e demo-prod -R "$REPO"
echo "" && echo "demo-stage secrets:" && gh secret list -e demo-stage -R "$REPO"
echo "" && echo "demo-stage variables:" && gh variable list -e demo-stage -R "$REPO"
