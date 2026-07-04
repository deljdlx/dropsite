FROM php:8.5-apache

# Installeur d'extensions robuste (gère deps système, configure, cleanup).
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/bin/

# --- Outils système + extensions PHP (runtime + dev) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip msmtp \
    && install-php-extensions \
        pdo_mysql mysqli zip intl gd bcmath exif pcntl opcache xdebug \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Node.js 22 LTS + corepack (pnpm / yarn) ---
COPY --from=node:22-bookworm /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && chmod +x /usr/local/bin/corepack \
 && corepack enable

# --- Composer ---
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# --- Modules Apache : vhost_alias (docroot dynamique), rewrite, headers ---
RUN a2enmod vhost_alias rewrite headers \
    && a2dissite 000-default

# --- Courrier PHP -> Mailpit (service `mailpit`, port SMTP 1025) ---
RUN printf '%s\n' \
        'account default' \
        'host mailpit' \
        'port 1025' \
        'from noreply@localhost' \
        'auth off' \
        'tls off' \
        > /etc/msmtprc \
    && chmod 644 /etc/msmtprc

COPY php.ini /usr/local/etc/php/conf.d/zz-sandbox.ini
COPY xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini
COPY vhost.conf /etc/apache2/sites-available/vhost.conf
RUN a2ensite vhost

# Vite dev server (HMR) exposé par la toolchain Node (démarré à la demande).
EXPOSE 80 5173
