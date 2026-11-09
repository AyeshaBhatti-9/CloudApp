#!/bin/bash
# User data for the APP-tier launch template.
# Runs once at first boot of every instance the Auto Scaling Group creates.
# No secrets live here: they are read from SSM Parameter Store at run time.
# (Deliberately no "set -x", which would print secrets into the log.)
set -eo pipefail
exec > >(tee /var/log/cloudops-userdata.log) 2>&1

REGION=eu-north-1
IMAGE=ghcr.io/ayeshabhatti-9/cloudops-backend:latest

# --- 1. Install Docker and the AWS CLI -------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io unzip curl
systemctl enable --now docker

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

# --- 2. Read settings and secrets from Parameter Store ---------------------
get() {
  aws ssm get-parameter --region "$REGION" --name "/cloudops/$1" \
    --with-decryption --query Parameter.Value --output text
}

DB_HOST=$(get db-host)
DB_USER=$(get db-user)
DB_NAME=$(get db-name)
DB_PASS=$(get db-password)
DB_PASS_ENC=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$DB_PASS")

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

# --- 3. Pull the private image and start the backend -----------------------
get ghcr-token | docker login ghcr.io -u "$(get ghcr-username)" --password-stdin
docker pull "$IMAGE"
docker rm -f cloudops-api 2>/dev/null || true
docker run -d \
  --name cloudops-api \
  --restart unless-stopped \
  --log-driver awslogs \
  --log-opt awslogs-region=eu-north-1 \
  --log-opt awslogs-group=/cloudops/app \
  --log-opt awslogs-stream="$(hostname)" \
  -p 8000:8000 \
  --env-file /etc/cloudops/api.env \
  "$IMAGE"