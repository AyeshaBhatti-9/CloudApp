FROM nginx:1.27-alpine

# The official nginx image runs envsubst on files in /etc/nginx/templates
# at startup and writes the result to /etc/nginx/conf.d/
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY static /usr/share/nginx/html

# Defaults suit docker-compose; override both at runtime on AWS
ENV API_UPSTREAM=http://api:8000 \
    DNS_RESOLVER=127.0.0.11

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost/healthz || exit 1