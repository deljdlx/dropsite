# Déploiement serveur (prod)

Guide pour déployer `dropsite` sur un serveur où **Traefik est l'edge partagé**
(un seul reverse-proxy possède `:80`/`:443`, toutes les stacks s'y branchent).

> Flux de travail : **on ne modifie jamais les fichiers directement sur le
> serveur**. On commite en local → push GitHub → `git pull` sur le serveur.
> Seuls les fichiers hors-git restent locaux au serveur : `traefik/.env`
> (secrets) et `traefik/acme/` (certificats), tous deux gitignorés.

## 1. Prérequis serveur

- Docker + Docker Compose.
- Un enregistrement **DNS wildcard** `*.deljdlx.fr` → IP du serveur (chez Gandi).
  Vérif : `dig +short A nimporte.deljdlx.fr` doit renvoyer l'IP du serveur.
- **Un seul** service peut tenir `:80`/`:443`. Si une autre stack les publie
  (`ports: ["80:80"]`), il y a conflit → l'edge ne démarrera pas. Les stacks
  applicatives ne publient PAS ces ports : elles passent par Traefik (labels).

## 2. Cloner le dépôt

```bash
cd ~/stack
git clone git@github.com:deljdlx/dropsite.git
cd dropsite
```

## 3. Secrets de l'edge (hors git)

```bash
cd traefik
cp .env.example .env
```

Éditer `traefik/.env` :

```ini
DOMAIN=deljdlx.fr
# Personal Access Token Gandi (droit gestion DNS de la zone) — SECRET
GANDIV5_PERSONAL_ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Le reste de la config ACME (email, provider `gandiv5`, autorité Let's Encrypt)
est dans `traefik/traefik.yml` — voir §7 pour le *pourquoi*.

## 4. Lancer l'edge Traefik (avec ACME)

L'edge se lance **en premier** (il crée le réseau `web`). L'override prod active
l'ACME DNS-01 wildcard :

```bash
cd ~/stack/dropsite/traefik
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Vérifier l'émission du certificat wildcard (peut prendre 1-2 min : d'abord
`Register...`, puis l'obtention via le challenge DNS) :

```bash
# ⚠️ un acme.json ~3400 octets = COMPTE seul (pas encore le cert).
# La vérif fiable : "Certificates" ne doit plus être null...
docker exec traefik sh -c 'cat /etc/traefik/acme/acme.json' | grep -q '"Certificates": *null' \
  && echo "cert pas encore émis" || echo "cert présent"

# ...et l'émetteur servi doit être Let's Encrypt (et non "TRAEFIK DEFAULT CERT") :
echo | openssl s_client -connect 127.0.0.1:443 -servername traefik.deljdlx.fr 2>/dev/null \
  | openssl x509 -noout -issuer
```

## 5. Lancer la stack sandbox

```bash
cd ~/stack/dropsite/sandbox
cp .env.example .env        # ajuster DOMAIN=deljdlx.fr + creds MySQL
docker compose up -d
```

Vérifier :

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://demo.deljdlx.fr/                       # 200
# HTTPS avec validation de la chaîne : http_code=200 ET ssl_verify=0 (cert de confiance)
curl -s -o /dev/null -w 'code=%{http_code} ssl_verify=%{ssl_verify_result}\n' https://demo.deljdlx.fr/
```

## 6. Mettre à jour (après un changement)

```bash
# En local
git add -A && git commit -m "..." && git push

# Sur le serveur
cd ~/stack/dropsite
git pull
# relancer la/les stack(s) impactée(s)
cd traefik && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
cd ../sandbox && docker compose up -d
```

## 7. Points de compréhension (pièges rencontrés)

Ces règles expliquent *pourquoi* la config est faite ainsi.

1. **Un seul edge possède `:80`/`:443`.** Deux Traefik (ou un Traefik + une app
   qui bind ces ports) ne cohabitent pas. Sur un serveur qui a déjà un proxy,
   soit on migre dessus, soit on ne déploie pas l'edge de dropsite.

2. **Noms de routeurs uniques sur un edge partagé.** Traefik agrège les labels
   de TOUS les conteneurs. Deux routeurs de même nom → `router defined multiple
   times` → le routeur est **rejeté** (→ 404). D'où le préfixe `dropsite-` sur
   tous nos routeurs/services.

3. **Le fichier statique `traefik.yml` n'expanse PAS les `${...}`.** Traefik lit
   sa config statique depuis une seule source ; si un fichier est monté, les
   variables `TRAEFIK_*` sont ignorées. Le résolveur ACME est donc écrit **en
   dur** dans `traefik.yml` (valeurs non secrètes). Seul le **token** du provider
   passe par l'environnement — il est lu directement par lego, pas par la config
   statique (`GANDIV5_PERSONAL_ACCESS_TOKEN` dans `docker-compose.prod.yml`).

4. **Wildcard = DNS-01 obligatoire (pas HTTP-01).** HTTP-01 délivre un cert par
   hôte concret ; nos sites dynamiques passent par un routeur wildcard
   `HostRegexp` sans domaine fixe → HTTP-01 ne sait pas quoi demander. DNS-01
   émet un seul cert `*.deljdlx.fr` qui couvre tout par SNI.

5. **Routeur dédié pour l'acquisition du cert.** Sur un routeur, la clé `tls` ne
   peut pas être à la fois une feuille (`tls=true`) et un nœud
   (`tls.certresolver`). On utilise donc un routeur séparé `dropsite-wildcard`
   qui ne porte que des sous-clés `tls.*`. Le cert obtenu va dans le store et est
   servi par SNI à tous les autres routeurs (qui gardent `tls: true`).

6. **Ne pas fournir de cert self-signed couvrant les domaines ACME.** Si un cert
   « fourni » couvre déjà `*.deljdlx.fr`, Traefik décide « No ACME certificate
   generation required » et ne demande jamais le vrai. En prod, pas de
   self-signed sur ces domaines (le dev, lui, utilise le cert interne de Traefik).

7. **Staging avant prod (optionnel).** Par défaut `traefik.yml` pointe déjà sur
   l'autorité **production**. Pour tester sans consommer les quotas Let's Encrypt,
   basculer `caServer` sur *staging* (commentaire dans `traefik.yml`). En
   **changeant d'autorité**, il faut **vider `acme/acme.json`** (le compte staging
   n'est pas valide en prod). Le fichier appartient à root (créé par Traefik) →
   le supprimer via un conteneur root, pas en direct :
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml down
   docker run --rm -v "$PWD/acme:/acme" alpine rm -f /acme/acme.json
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   ```

## 8. Migrer une ancienne stack (v2 → cet edge v3)

Pour brancher une stack existante sur ce Traefik v3, adapter ses labels :

- Renommer les routeurs en identifiants **uniques**.
- Syntaxe **v3** (`HostRegexp(`^…$`)` et non `{host:.+}`, plus de middleware
  chain propre à l'ancien proxy).
- TLS : `traefik.http.routers.<nom>.tls.certresolver=letsencrypt` (le cert
  wildcard couvre déjà `*.deljdlx.fr`, donc souvent un simple `tls: true` suffit).
- Réseau : rejoindre `web` (`external: true`).
