# Composer
FROM composer as vendor

ENV COMPOSER_ALLOW_SUPERUSER 1

COPY app app/
COPY database database/
# COPY tests tests/
COPY composer.json composer.lock ./

RUN set -x \
    && composer install \
        --ignore-platform-reqs \
        --no-interaction \
        --no-plugins \
        --no-scripts \
        --no-suggest \
        --no-dev \
        --classmap-authoritative


# Node
FROM node:8-alpine as frontend

WORKDIR /app

COPY artisan package.json webpack.mix.js yarn.lock ./
COPY resources/assets/ resources/assets/

RUN set -x \
    && yarn install \
        --frozen-lockfile \
        --no-cache \
        --no-progress \
    && yarn run production \
        --no-progress \
    && yarn cache clean

COPY public public/


FROM alpine as packer

WORKDIR /app

COPY --chown=82:82 ./ .
COPY --from=vendor --chown=82:82 /app/vendor vendor/
COPY --from=frontend --chown=82:82 /app/public public/

RUN set -x \
    && apk add --no-cache xz \
    && ln -s ../storage/app/public /app/public/storage \
    && XZ_OPT=-9e tar -Jcf /app.tar.xz -C /app . \
    && apk del xz


# Final Image
FROM php:7.2-fpm-alpine

RUN set -x \
    && apk add --no-cache \
        fcgi \
        rsync \
    && docker-php-ext-install mysqli pdo_mysql \
    && rm -rf /tmp/* /var/cache/apk/* \
    && sed -ri \
        -e 's/;(ping\.path)/\1/' /usr/local/etc/php-fpm.d/www.conf \
    && cd "$PHP_INI_DIR" \
    && ln -s php.ini-production php.ini \
    && sed -ri \
        -e 's/^(expose_php).*$/\1 = Off/' \
        php.ini-production

WORKDIR /var/www/html
VOLUME /var/www/html

COPY --from=packer /app.tar.xz /usr/src/app.tar.xz
COPY --chown=root docker/entrypoint docker/health-check /

HEALTHCHECK --interval=1m --timeout=5s \
    CMD /health-check

CMD ["/entrypoint"]
