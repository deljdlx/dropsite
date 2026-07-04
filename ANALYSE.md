# Analyse — Stack Traefik + Apache (sous-domaines dynamiques)

## Objectif

Un socle d'hébergement où **créer un dossier suffit à publier un site** sous son
propre sous-domaine, sans reconfigurer quoi que ce soit. Usage principal : monter
et tester des sites/POCs rapidement (dev, et prod paramétrable). Les « vraies »
applications vivront dans **leurs propres stacks**, branchées sur le même edge
Traefik.

## Modèle : Traefik = edge mutualisé

Traefik n'appartient à aucune application. C'est un reverse-proxy long-running,
autonome, qui **possède un réseau Docker externe partagé** (`web`). Chaque stack
qui veut être exposée **rejoint ce réseau** et se déclare via ses **labels
Traefik**. Traefik les découvre seul (provider Docker).

```
                         TRAEFIK  (stack à part, tourne en permanence)
                         owns network `web` · TLS/ACME · dashboard
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
 ┌──────▼───────┐                 ┌──────▼───────┐                 ┌──────▼───────┐
 │   SANDBOX     │                │ VRAIE APP #1 │                 │ VRAIE APP #2 │
 │ apache mod_php│                │ (nginx+FPM…) │                 │ (node, go…)  │
 │ mod_vhost_alias│               │ app1.dom.fr  │                 │ app2.dom.fr  │
 │ *.localhost   │                │ labels perso │                 │ labels perso │
 │ = N sites     │                │              │                 │              │
 └───────────────┘                └──────────────┘                 └──────────────┘
   1 dossier = 1 site           1 stack = 1 app              chacune wirée à Traefik
```

## Routage à deux étages

Le mot « dynamique » n'a pas le même sens à chaque étage :

- **Traefik** : un **unique router wildcard** `HostRegexp(^.+\.localhost$)`
  qui route TOUT vers Apache, en préservant le header `Host`. Jamais retouché
  quand on ajoute un site.
- **Apache** (`mod_vhost_alias`) : `VirtualDocumentRoot /var/www/sites/%1/public`
  → `%1` = premier label du Host → dossier. Créer `sites/foo/public/` publie
  `foo.localhost` **sans reload**.

```
   *.localhost (dev)  |  *.tondomaine.fr (prod)
                    │
         ┌──────────▼───────────┐
         │       TRAEFIK        │  TLS (self-signed/mkcert dev · ACME DNS-01 prod)
         │  1 router wildcard   │  HostRegexp catch-all → apache
         │  + routers exacts    │  traefik.$DOMAIN, mail.$DOMAIN (priorité +)
         └──────────┬───────────┘
                    │ Host préservé
         ┌──────────▼───────────┐
         │   APACHE + mod_php   │  php:8.5-apache
         │   mod_vhost_alias    │  VirtualDocumentRoot /var/www/sites/%1/public
         └──────────┬───────────┘
                    │
      MySQL 8   ·   Mailpit (SMTP 1025 · UI mail.$DOMAIN)
```

## Décisions

| Sujet | Décision | Raison |
|---|---|---|
| Topologie | Edge Traefik mutualisé + réseau externe `web` | Un proxy, N stacks branchées sans le toucher |
| Structure repo | `traefik/` (edge) et `sandbox/` (apache) = stacks sœurs isolées | Chaque stack son dossier |
| Dynamique | Apache `mod_vhost_alias` ; Traefik = 1 router wildcard | Le seul point « intelligent » est Apache |
| PHP | `mod_php` (`php:8.5-apache`) | Marche direct avec `VirtualDocumentRoot`, simple |
| Domaine dev | `*.localhost` | Zéro DNS (le TLD `.localhost` résout vers 127.0.0.1) |
| Domaine prod | `DOMAIN` en `.env`, wildcard `*.dom.fr` | Paramétrable |
| TLS dev | wildcard self-signed (openssl) ; mkcert si dispo | Pas de dépendance externe |
| TLS prod | ACME DNS-01 wildcard, provider **paramétrable (à brancher)** | Seul moyen de garder le TLS dynamique |
| Toolchain dev | Composer, Xdebug, Node 22, npm/pnpm dans l'image Apache | Vrai poste de dev full-stack (pas qu'un runtime) |
| Vite HMR | dev server exposé sur `vite.localhost` (websocket) | Hot-reload live derrière Traefik |
| Services sandbox | MySQL 8 · Mailpit (via `msmtp`) | Minimum utile pour des sites PHP |
| Dashboard | `traefik.localhost` (priorité > wildcard) | Visibilité des routes en dev |

## Points d'attention (implémentation)

1. **Priorités de routers** : les routers exacts (`traefik.$DOMAIN`,
   `mail.$DOMAIN`, `vite.$DOMAIN`) doivent avoir une **`priority` supérieure** au
   wildcard `HostRegexp`, sinon ils sont happés par le catch-all.
2. **HTTP + HTTPS** : `tls: true` rend un router **exclusivement HTTPS**. Pour que
   le HTTP réponde aussi en dev (sans avertissement de cert), chaque service a
   **deux routers** : un sur `web` (sans TLS), un sur `websecure` (avec TLS).
3. **Réseau `web`** : possédé/créé par l'edge (`name: web`) ; déclaré
   `external: true` côté sandbox. **L'edge se lance en premier.**
4. **ACME DNS-01 paramétrable** : le resolver est prévu mais le provider DNS
   n'est pas encore branché → la **prod wildcard ne fonctionnera qu'une fois le
   provider configuré**. Dev (self-signed) non bloqué.
5. **Image Apache custom** (pas l'image stock) : extensions PHP via
   **`install-php-extensions`** (mlocati) — robuste, contourne un bug de
   compilation d'`intl` sur `php:8.5` (Debian trixie). Ajoute aussi Composer,
   Node, Xdebug et le `sendmail_path` → Mailpit (`msmtp`).
6. **Vite HMR** : un seul dev server à la fois (port `5173` unique du conteneur).
   Cohérent avec un usage sandbox « un site en dev à la fois ». Le websocket HMR
   passe nativement par Traefik (routeur `vite.$DOMAIN`).
7. **`AllowOverride All`** sur `sites/` : pour que les `.htaccess` des
   front-controllers (Laravel/Symfony) fonctionnent malgré le docroot dynamique.

## Arborescence cible

```
<repo>/
├── ANALYSE.md
├── traefik/                     ← STACK EDGE
│   ├── docker-compose.yml       # traefik seul ; crée & possède le réseau `web`
│   ├── traefik.yml              # config statique (entrypoints, providers, ACME)
│   ├── dynamic/
│   │   ├── tls.yml              # dev : cert wildcard self-signed
│   │   └── middlewares.yml      # headers sécurité, redirections
│   └── certs/                   # cert dev (gitignored)
└── sandbox/                     ← STACK APACHE
    ├── docker-compose.yml       # apache + mysql + mailpit ; réseau `web` external
    ├── apache/
    │   ├── Dockerfile           # php:8.5 + install-php-extensions + Node + Composer + Xdebug
    │   ├── vhost.conf           # VirtualDocumentRoot /var/www/sites/%1/public
    │   ├── php.ini
    │   └── xdebug.ini           # Xdebug actif (host.docker.internal:9003)
    └── sites/
        └── demo/                # ← 1 dossier = 1 site = 1 sous-domaine
            ├── public/index.php
            ├── package.json     # exemple Vite (HMR)
            ├── vite.config.js
            └── src/main.js
```

## Geste « nouveau site »

```bash
mkdir -p sandbox/sites/foo/public
echo '<?php phpinfo();' > sandbox/sites/foo/public/index.php
# → https://foo.localhost   (rien d'autre)
```

## Plan d'implémentation

1. Edge Traefik (compose + `traefik.yml` + réseau `web` + dashboard).
2. TLS dev (wildcard self-signed + `dynamic/tls.yml`).
3. Stack sandbox (Dockerfile Apache + `vhost.conf` + labels wildcard).
4. MySQL 8 + `pdo_mysql`.
5. Mailpit + `msmtp`.
6. ACME DNS-01 placeholder + doc `.env` prod.
7. Toolchain dev full-stack dans l'image (Composer, Xdebug, Node, npm/pnpm).
8. Vite HMR câblé via Traefik (`vite.$DOMAIN` → port 5173, websocket).

Chaque étape est vérifiable dans le navigateur avant de passer à la suivante.
