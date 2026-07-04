# Makefile dropsite — raccourcis dev & prod.
# `make` ou `make help` affiche les cibles disponibles.

# Compose : on pilote les 2 stacks depuis la racine via -f (le project dir = dossier
# du 1er fichier, donc .env et chemins relatifs se résolvent correctement).
EDGE       := docker compose -f traefik/docker-compose.yml
EDGE_PROD  := docker compose -f traefik/docker-compose.yml -f traefik/docker-compose.prod.yml
SANDBOX    := docker compose -f sandbox/docker-compose.yml

.DEFAULT_GOAL := help
.PHONY: help init up down restart build ps logs sh site vite \
        prod-up prod-down prod-logs prod-cert prod-cert-reset

help: ## Affiche cette aide
	@echo "dropsite — cibles disponibles :"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- Dev (local)
init: ## Prépare les .env (copie depuis .env.example)
	@cp -n traefik/.env.example traefik/.env  && echo "traefik/.env créé" || true
	@cp -n sandbox/.env.example sandbox/.env  && echo "sandbox/.env créé" || true

up: ## Dev : démarre l'edge + la sandbox (localhost)
	$(EDGE) up -d
	$(SANDBOX) up -d
	@echo "→ http://demo.localhost · http://traefik.localhost · http://mail.localhost"

down: ## Dev : arrête l'edge + la sandbox
	$(SANDBOX) down
	$(EDGE) down

restart: down up ## Dev : redémarre tout

build: ## Reconstruit l'image Apache de la sandbox
	$(SANDBOX) build

ps: ## Statut des conteneurs
	@$(EDGE) ps
	@$(SANDBOX) ps

logs: ## Suit les logs de l'edge Traefik
	$(EDGE) logs -f traefik

sh: ## Ouvre un shell dans le conteneur apache
	$(SANDBOX) exec apache bash

# --------------------------------------------------------------- Sites / Vite
site: ## Crée un site (make site name=foo)
	@test -n "$(name)" || { echo "Usage : make site name=<slug>"; exit 1; }
	@mkdir -p sandbox/sites/$(name)/public
	@echo '<?php phpinfo();' > sandbox/sites/$(name)/public/index.php
	@echo "→ site '$(name)' créé : http://$(name).localhost (dev)"

vite: ## Lance le dev server Vite d'un site (make vite name=foo)
	@test -n "$(name)" || { echo "Usage : make vite name=<slug>"; exit 1; }
	$(SANDBOX) exec apache sh -c 'cd sites/$(name) && npm install && npm run dev'

# ---------------------------------------------------------------- Prod (serveur)
prod-up: ## Prod : démarre l'edge (ACME wildcard) + la sandbox
	$(EDGE_PROD) up -d
	$(SANDBOX) up -d

prod-down: ## Prod : arrête l'edge + la sandbox
	$(SANDBOX) down
	$(EDGE_PROD) down

prod-logs: ## Prod : suit les logs de l'edge
	$(EDGE_PROD) logs -f traefik

prod-cert: ## Prod : affiche l'émetteur du certificat servi (DOMAIN=... requis)
	@test -n "$(DOMAIN)" || { echo "Usage : make prod-cert DOMAIN=deljdlx.fr"; exit 1; }
	@echo | openssl s_client -connect 127.0.0.1:443 -servername traefik.$(DOMAIN) 2>/dev/null \
	  | openssl x509 -noout -issuer -enddate

prod-cert-reset: ## Prod : vide acme.json (root) et relance — bascule staging<->prod
	$(EDGE_PROD) down
	docker run --rm -v "$$(pwd)/traefik/acme:/acme" alpine rm -f /acme/acme.json
	$(EDGE_PROD) up -d
