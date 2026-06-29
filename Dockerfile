FROM php:8.4-fpm-bullseye as build
ARG nc_download_url=https://download.nextcloud.com/.customers/server/33.0.6-8493f1bc/nextcloud-33.0.6-enterprise.zip
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
RUN { \
      apt-get -q update > /dev/null && apt-get -q install -y \
      apt-utils \
      build-essential \
      freetype* \
      libgmp* \
      libicu* \
      libldap* \
      libmagickwand* \
      libmemcached* \
      libpng* \
      libpq* \
      libweb* \
      libzip* \
      npm \
      zlib* \
      gnupg2 \
      make \
      npm \
      patch \
      ssl-cert \
      unzip \
      wget \
      > /dev/null; \
      pecl -q install apcu \
      imagick \
      memcached \
      redis \
      > /dev/null; \
      docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
      docker-php-ext-install -j "$(nproc)" \
      bcmath \
      bz2 \
      exif \
      gd \
      gmp \
      intl \
      ldap \
      opcache \
      pcntl \
      pdo_mysql \
      pdo_pgsql \
      sysvsem \
      zip \
      ; \
      docker-php-ext-enable \
      imagick \
      apcu \
      memcached \
      redis \
      ; \
      { \
        echo 'opcache.interned_strings_buffer=64'; \
        echo 'opcache.memory_consumption=512'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
      } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
      { \
        echo 'extension=apcu.so'; \
        echo 'apc.enable_cli=1'; \
        echo 'apc.shm_size=256M'; \
      } > /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini; \
      { \
        echo 'memory_limit = 2G'; \
        echo 'upload_max_filesize=30G'; \
        echo 'post_max_size=30G'; \
        echo 'max_execution_time=86400'; \
        echo 'max_input_time=86400'; \
      } > /usr/local/etc/php/conf.d/nce.ini; \
    }
## DONT ADD STUFF BETWEEN HERE
RUN wget -q ${nc_download_url} -O /tmp/nextcloud.zip && cd /tmp && unzip -qq /tmp/nextcloud.zip && cd /tmp/nextcloud \
  && mkdir -p /var/www/html/data && echo '# Nextcloud data directory' > /var/www/html/data/.ncdata && mkdir /var/www/html/config \
  && cp -a /tmp/nextcloud/* /var/www/html && cp -a /tmp/nextcloud/.[^.]* /var/www/html \
  && chown -R www-data:root /var/www/html && chmod +x /var/www/html/occ; \
  php /var/www/html/occ integrity:check-core
## AND HERE, OR CODE INTEGRITY CHECK MIGHT FAIL, AND IMAGE WILL NOT BUILD

FROM php:8.4-fpm-bullseye
ARG APACHE_LOG_DIR=/var/log/apache2
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

RUN apt update && apt install -y \
  apache2 \
  libfreetype6 \
  libgmp10 \
  libicu67 \
  libldap-2.4-2 \
  libmagickwand-6.q16-6 \
  libmagickwand-6.q16hdri-6 \
  libmemcached11 \
  libpng16-16 \
  libpq5 \
  libwebm1 \
  libwebp6 \
  libwebpmux3 \
  libwebsockets16 \
  libzip4 \
  mariadb-client \
  npm \
  redis-tools \
  ssl-cert \
  supervisor \
  vim \
  wget \
  zlib1g \
  && wget -q https://downloads.rclone.org/rclone-current-linux-amd64.deb \
  && dpkg -i ./rclone-current-linux-amd64.deb \
  && rm ./rclone-current-linux-amd64.deb

## Apache: serve via mpm_event + php-fpm over a unix socket (mod_php is gone).
RUN a2dismod -f mpm_prefork mpm_worker 2>/dev/null; \
    a2enmod mpm_event proxy proxy_fcgi setenvif headers env mime rewrite dir deflate ssl remoteip; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf && a2enconf servername; \
    sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf; \
    sed -i 's/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
    mkdir -p /run/php && chown www-data:www-data /run/php; \
    chmod -R 777 ${APACHE_LOG_DIR}

## Apache config (lives in /etc/apache2, untouched by the /usr/local copy below).
## php-fpm proxy tuning: long timeouts so 30G uploads / long jobs don't 504.
COPY ./apache-fpm.conf /etc/apache2/conf-available/zzz-nextcloud-fpm.conf
COPY ./mpm_event.conf /etc/apache2/mods-available/mpm_event.conf
COPY ./000-default.conf /etc/apache2/sites-available/
COPY ./supervisord.conf /etc/supervisor/supervisord.conf
COPY --chown=root:root ./cron.sh /cron.sh
RUN a2enconf zzz-nextcloud-fpm && a2ensite 000-default

## Bring in the built PHP runtime + Nextcloud, THEN lay down the fpm pool so the
## /usr/local copy can't restore the stock www.conf / zz-docker.conf (listen=9000).
COPY --from=build /var/www/html /var/www/html
COPY --from=build /usr/local /usr/local
COPY ./php-fpm-www.conf /usr/local/etc/php-fpm.d/zzz-nextcloud.conf
RUN rm -f /usr/local/etc/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/zz-docker.conf

## ADD www-data to tty group
RUN usermod -a -G tty www-data

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
