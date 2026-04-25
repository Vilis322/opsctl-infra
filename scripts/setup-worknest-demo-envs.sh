#!/bin/bash
# Setup GitHub environment secrets for WorkNest demo-prod and demo-stage
# Usage: SSH_KEY_FILE=~/.ssh/id_ed25519_demo ./setup-worknest-demo-envs.sh

set -euo pipefail

REPO="Vilis322/worknest"

if [[ -z "${SSH_KEY_FILE:-}" ]]; then
  echo "ERROR: SSH_KEY_FILE not set"
  exit 1
fi
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "ERROR: SSH key file not found: $SSH_KEY_FILE"
  exit 1
fi

echo "=== Deleting old environments ==="
for OLD_ENV in demo; do
  echo "Deleting: $OLD_ENV"
  gh api --method DELETE "repos/$REPO/environments/$OLD_ENV" --silent 2>/dev/null || echo "  (not found)"
done

echo ""
echo "=== Creating environments ==="
for ENV in demo-prod demo-stage; do
  gh api --method PUT "repos/$REPO/environments/$ENV" --silent
  echo "Created: $ENV"
done

echo ""
echo "=== Setting demo-prod secrets ==="

gh secret set SSH_HOST      -b "${DEMO_VPS_IP}"  -e demo-prod -R "$REPO"
gh secret set SSH_USER      -b "root"            -e demo-prod -R "$REPO"
gh secret set SSH_KEY       < "$SSH_KEY_FILE"    -e demo-prod -R "$REPO"
gh secret set SSH_PORT      -b "22"              -e demo-prod -R "$REPO"
gh secret set DATABASE_URL  -b "postgresql://worknest_demo:${WORKNEST_DEMO_DB_PASSWORD}@localhost:5432/worknest_demo"     -e demo-prod -R "$REPO"
gh secret set REDIS_URL     -b "redis://localhost:6379/4"  -e demo-prod -R "$REPO"
gh secret set JWT_SECRET    -b "${GENERATED_SECRET}"  -e demo-prod -R "$REPO"

echo ""
echo "=== Setting demo-prod variables ==="

gh variable set APP_DIR        -b "/var/www/worknest-demo"       -e demo-prod -R "$REPO"
gh variable set PM2_PREFIX     -b "worknest-demo"                -e demo-prod -R "$REPO"
gh variable set DOMAIN         -b "worknest.opsctl.tech"         -e demo-prod -R "$REPO"
gh variable set BACKEND_PORT   -b "5011"                         -e demo-prod -R "$REPO"
gh variable set FRONTEND_PORT  -b "5001"                         -e demo-prod -R "$REPO"

echo ""
echo "=== Setting demo-stage secrets ==="

gh secret set SSH_HOST      -b "${DEMO_VPS_IP}"  -e demo-stage -R "$REPO"
gh secret set SSH_USER      -b "root"            -e demo-stage -R "$REPO"
gh secret set SSH_KEY       < "$SSH_KEY_FILE"    -e demo-stage -R "$REPO"
gh secret set SSH_PORT      -b "22"              -e demo-stage -R "$REPO"
gh secret set DATABASE_URL  -b "postgresql://worknest_demo_stage:${WORKNEST_STAGE_DB_PASSWORD}@localhost:5432/worknest_demo_stage"  -e demo-stage -R "$REPO"
gh secret set REDIS_URL     -b "redis://localhost:6379/5"  -e demo-stage -R "$REPO"
gh secret set JWT_SECRET    -b "${GENERATED_SECRET}"  -e demo-stage -R "$REPO"

echo ""
echo "=== Setting demo-stage variables ==="

gh variable set APP_DIR        -b "/var/www/worknest-demo-stage"  -e demo-stage -R "$REPO"
gh variable set PM2_PREFIX     -b "worknest-stage"                -e demo-stage -R "$REPO"
gh variable set DOMAIN         -b "worknest.dev"                  -e demo-stage -R "$REPO"
gh variable set BACKEND_PORT   -b "5012"                          -e demo-stage -R "$REPO"
gh variable set FRONTEND_PORT  -b "5002"                          -e demo-stage -R "$REPO"

echo ""
echo "=== Done! Verifying ==="
echo "demo-prod secrets:" && gh secret list -e demo-prod -R "$REPO"
echo "" && echo "demo-prod variables:" && gh variable list -e demo-prod -R "$REPO"
echo "" && echo "demo-stage secrets:" && gh secret list -e demo-stage -R "$REPO"
echo "" && echo "demo-stage variables:" && gh variable list -e demo-stage -R "$REPO"
