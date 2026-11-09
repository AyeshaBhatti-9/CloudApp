#!/bin/bash
# User data for the WEB-tier launch template.
# Starts the nginx frontend container and points it at the internal ALB.
# No secrets here: registry credentials and the ALB address come from SSM.
# (Deliberately no "set -x", which would print secrets into the log.)
set -eo pipefail
exec > >(tee /var/log/cloudops-userdata.log) 2>&1

REGION=eu-north-1
IMAGE=ghcr.io/ayeshabhatti-9/cloudops-frontend:latest

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

# --- 2. Read settings from Parameter Store ---------------------------------
get() {
  aws ssm get-parameter --region "$REGION" --name "/cloudops/$1" \
    --with-decryption --query Parameter.Value --output text
}

API_DNS=$(get internal-alb-dns)

# --- 3. Pull the private image and start the web tier ----------------------
get ghcr-token | docker login ghcr.io -u "$(get ghcr-username)" --password-stdin
docker pull "$IMAGE"
docker rm -f cloudops-web 2>/dev/null || true

# 10.0.0.2 is the Amazon-provided DNS resolver of the 10.0.0.0/16 VPC
docker run -d \
  --name cloudops-web \
  --restart unless-stopped \
  -p 80:80 \
  -e API_UPSTREAM="http://${API_DNS}" \
  -e DNS_RESOLVER=10.0.0.2 \
  "$IMAGE"