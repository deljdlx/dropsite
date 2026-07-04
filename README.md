# Stack Traefik + Sandbox Apache (sous-domaines dynamiques)

Socle où **créer un dossier suffit à publier un site** sous son propre
sous-domaine. Voir [ANALYSE.md](ANALYSE.md) pour la conception détaillée.

```
traefik/    ← edge mutualisé (reverse-proxy, TLS, dashboard) — possède le réseau `web`
sandbox/    ← ferme de sites (Apache mod_php + mod_vhost_alias, MySQL, Mailpit)
```

## Démarrer

L'edge doit être lancé **en premier** (il crée le réseau `web`) :

```bash
# 1) Edge Traefik
cd traefik
cp -n .env.example .env
bash certs/generate.sh          # cert wildcard self-signed (dev)
docker compose up -d

# 2) Sandbox
cd ../sandbox
cp -n .env.example .env
docker compose up -d
```

## Ajouter un site

```bash
mkdir -p sandbox/sites/monsite/public
echo '<?php phpinfo();' > sandbox/sites/monsite/public/index.php
# → https://monsite.localhost   (aucun redémarrage)
```

Le TLD `.localhost` résout automatiquement vers `127.0.0.1` : aucune config DNS.
Le certificat étant self-signed en dev, le navigateur affiche un avertissement
(ou installer `mkcert` pour un cert de confiance, cf. `traefik/certs/generate.sh`).

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
- **Xdebug** actif en permanence (mode `debug,develop`, `start_with_request=yes`),
  se connecte à l'IDE sur `host.docker.internal:9003` (idekey `VSCODE`).
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

## Prod (à finaliser)

Le domaine est paramétré par `DOMAIN` dans les deux `.env`. Le certificat wildcard
prod passe par **ACME DNS-01**, dont le provider reste **à brancher** :

1. Renseigner `ACME_DNS_PROVIDER` (ex. `cloudflare`, `ovh`…) dans `traefik/.env`.
2. Fournir les credentials du provider au conteneur Traefik (variables
   d'environnement dédiées, cf. doc Traefik du provider).
3. Ajouter `tls.certResolver: letsencrypt` aux routers concernés.

Tant que ce n'est pas fait, seul le dev (cert self-signed) fonctionne.
```
