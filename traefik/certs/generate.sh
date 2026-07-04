#!/usr/bin/env bash
# Génère un certificat wildcard self-signed pour le développement local.
# En prod, ce cert n'est pas utilisé (ACME DNS-01 prend le relais).
#
# Astuce : si `mkcert` est installé, préférer :
#   mkcert -cert-file local.crt -key-file local.key "docker.localhost" "*.docker.localhost"
# → certificat reconnu par le navigateur (pas d'avertissement).
set -euo pipefail
cd "$(dirname "$0")"

DOMAIN="${1:-docker.localhost}"

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout local.key -out local.crt \
  -days 3650 \
  -subj "/CN=*.${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN}"

echo "Certificat généré : local.crt / local.key pour *.${DOMAIN}"
