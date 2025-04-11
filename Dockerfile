FROM php:8.2-apache-bullseye as build
ARG nc_download_url=https://download.nextcloud.com/.customers/server/30.0.9-40791027/nextcloud-30.0.9-enterprise.zip
ARG APACHE_DOCUMENT_ROOT=/var/www/html
ARG APACHE_LOG_DIR=/var/log/apache2
ARG APACHE_RUN_DIR=/var/run/apache2
ARG APACHE_LOCK_DIR=/var/lock/apache2
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
      a2enmod dir env headers mime rewrite setenvif deflate ssl; \
      { \
        echo 'opcache.interned_strings_buffer=32'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
      } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
      { \
        echo 'extension=apcu.so'; \
        echo 'apc.enable_cli=1'; \
      } > /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini; \
      { \
        echo 'memory_limit = 2G'; \
        echo 'upload_max_filesize=30G'; \
        echo 'post_max_size=30G'; \
        echo 'max_execution_time=86400'; \
        echo 'max_input_time=86400'; \
      } > /usr/local/etc/php/conf.d/nce.ini; \
      echo "ServerName localhost" | tee /etc/apache2/conf-available/servername.conf \
      && a2enconf servername; \
      sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf; \
      sed -i 's/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
      chmod -R 777 ${APACHE_RUN_DIR} ${APACHE_LOCK_DIR} ${APACHE_LOG_DIR} ${APACHE_DOCUMENT_ROOT}; \
    }
COPY --chown=root:root ./000-default.conf /etc/apache2/sites-available/
## DONT ADD STUFF BETWEEN HERE
RUN wget -q ${nc_download_url} -O /tmp/nextcloud.zip && cd /tmp && unzip -qq /tmp/nextcloud.zip && cd /tmp/nextcloud \
  && mkdir -p /var/www/html/data && echo '# Nextcloud data directory' > /var/www/html/data/.ncdata && mkdir /var/www/html/config \
  && cp -a /tmp/nextcloud/* /var/www/html && cp -a /tmp/nextcloud/.[^.]* /var/www/html \
  && chown -R www-data:root /var/www/html && chmod +x /var/www/html/occ; \
  php /var/www/html/occ integrity:check-core
## AND HERE, OR CODE INTEGRITY CHECK MIGHT FAIL, AND IMAGE WILL NOT BUILD

FROM php:8.2-apache-bullseye
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

RUN apt update && apt install -y \
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
  vim \
  wget \
  zlib1g \
  && wget -q https://downloads.rclone.org/rclone-current-linux-amd64.deb \
  && dpkg -i ./rclone-current-linux-amd64.deb \
  && rm ./rclone-current-linux-amd64.deb

COPY --chown=root:root ./cron.sh /cron.sh
COPY --from=build /var/www/html /var/www/html
COPY --from=build /etc/apache2 /etc/apache2
COPY --from=build /usr/local /usr/local

## ADD www-data to tty group
RUN usermod -a -G tty www-data
