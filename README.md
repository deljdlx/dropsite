# Stack Traefik + Sandbox Apache (sous-domaines dynamiques)

Socle où **créer un dossier suffit à publier un site** sous son propre
sous-domaine. Voir [ANALYSE.md](ANALYSE.md) pour la conception détaillée.

```
traefik/    ← edge mutualisé (reverse-proxy, TLS, dashboard) — possède le réseau `web`
sandbox/    ← ferme de sites (Apache mod_php + mod_vhost_alias, MySQL, Mailpit)
```

## Démarrer

Le plus simple, via le **Makefile** (`make help` liste tout) :

```bash
make init    # prépare les .env
make up      # démarre l'edge + la sandbox (dev, localhost)
```

Équivalent manuel (l'edge d'abord — il crée le réseau `web`) :

```bash
cd traefik  && cp -n .env.example .env && docker compose up -d
cd ../sandbox && cp -n .env.example .env && docker compose up -d
```

## Ajouter un site

```bash
make site name=monsite        # scaffold sandbox/sites/monsite/public/index.php
# → http://monsite.localhost   (aucun redémarrage)
```

Le TLD `.localhost` résout automatiquement vers `127.0.0.1` : aucune config DNS.
En dev, préférer le **HTTP** (`http://monsite.localhost`) : le HTTPS utilise le
certificat interne auto-généré par Traefik → avertissement navigateur (normal).
Le HTTPS de confiance est géré en prod par ACME (voir [DEPLOY.md](DEPLOY.md)).

## URLs (dev)

| Service | URL |
|---|---|
| Un site | `https://<slug>.localhost` |
| Dashboard Traefik | `https://traefik.localhost` |
| Mailpit (mails) | `https://mail.localhost` |

## Services

- **MySQL 8** — accessible depuis un site via l'hôte `mysql` (réseau interne,
  aucun port publié). DB/user par défaut : `sandbox` / `sandbox`.
- **Mailpit** — capture tous les mails PHP (`mail()` → `msmtp` → Mailpit).

## Environnement de dev full-stack

Le conteneur `sandbox-apache` embarque une vraie toolchain de dev :

- **PHP 8.5** (mod_php) + extensions : `pdo_mysql`, `mysqli`, `intl`, `gd`,
  `bcmath`, `exif`, `pcntl`, `zip`, `opcache`.
- **Xdebug** installé mais **off par défaut** (prod-safe, zéro overhead).
  Pour débugger : `XDEBUG_MODE=develop,debug` dans `sandbox/.env` (se connecte à
  l'IDE sur `host.docker.internal:9003`, idekey `VSCODE`).
- **Composer 2**, **Node 22 LTS**, **npm**, **corepack** (pnpm / yarn).

Exécuter les outils dans le conteneur :

```bash
cd sandbox
docker compose exec apache sh -c 'cd sites/monsite && composer install'
docker compose exec apache sh -c 'cd sites/monsite && npm install'
```

## Vite (HMR live)

Le dev server Vite tourne dans le conteneur (port 5173) et est exposé par Traefik
sur `http://vite.localhost` (websocket HMR inclus, un seul site actif à la fois) :

```bash
docker compose exec apache sh -c 'cd sites/monsite && npm run dev'
```

Config Vite type (assets servis à l'app PHP, cf. `sites/demo/vite.config.js`) :
`server.origin = http://vite.localhost` et `server.hmr = { host: vite.localhost, clientPort: 80, protocol: ws }`.
La page PHP charge alors `http://vite.localhost/@vite/client` et son entrée JS.

## Prod

Le déploiement serveur (edge partagé, HTTPS wildcard via ACME DNS-01) est décrit
pas-à-pas dans **[DEPLOY.md](DEPLOY.md)**.
