#!/bin/bash
# Runs the CloudOps backend container on an app-tier EC2 instance.
# Reads every secret from SSM Parameter Store at run time, so nothing
# sensitive is stored in this file, the repo, or the launch template.
# Requires: docker, aws cli, python3, and an instance role that can read /cloudops/*
set -euo pipefail

REGION=eu-north-1
IMAGE=ghcr.io/ayeshabhatti-9/cloudops-backend:latest

get() {
  aws ssm get-parameter --region "$REGION" --name "/cloudops/$1" \
    --with-decryption --query Parameter.Value --output text
}

DB_HOST=$(get db-host)
DB_USER=$(get db-user)
DB_NAME=$(get db-name)
DB_PASS=$(get db-password)

# URL-encode the password in case it contains characters like @ : / #
DB_PASS_ENC=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$DB_PASS")

# Environment file readable by root only (never passed on the command line)
install -d -m 700 /etc/cloudops
umask 077
cat > /etc/cloudops/api.env <<EOF
DATABASE_URL=postgresql+psycopg://${DB_USER}:${DB_PASS_ENC}@${DB_HOST}:5432/${DB_NAME}?sslmode=require
APP_SECRET=$(get app-secret)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$(get admin-password)
CUSTOMER_USERNAME=customer
CUSTOMER_PASSWORD=$(get customer-password)
EOF

# Log in to the private registry using the read-only token, then pull and run
get ghcr-token | docker login ghcr.io -u "$(get ghcr-username)" --password-stdin
docker pull "$IMAGE"
docker rm -f cloudops-api 2>/dev/null || true
docker run -d \
  --name cloudops-api \
  --restart unless-stopped \
  -p 8000:8000 \
  --env-file /etc/cloudops/api.env \
  "$IMAGE"

echo "Backend started. Check: curl http://localhost:8000/health"