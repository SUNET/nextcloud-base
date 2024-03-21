FROM php:8.2-rc-apache-bullseye as apt
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
# Pre-requisites for the extensions
RUN set -ex; \
  apt-get -q update > /dev/null && apt-get -q install -y \
  apt-utils
RUN set -ex; \
  apt-get -q install -y \
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
  curl \
  gnupg2 \
  make \
  mariadb-client \
  npm \
  patch \
  redis-tools \
  ssl-cert \
  unzip \
  vim \
  wget > /dev/null

RUN wget -q https://downloads.rclone.org/rclone-current-linux-amd64.deb \
  && dpkg -i ./rclone-current-linux-amd64.deb \
  && rm ./rclone-current-linux-amd64.deb

FROM apt as php
ARG APACHE_DOCUMENT_ROOT=/var/www/html
ARG APACHE_LOG_DIR=/var/log/apache2
ARG APACHE_RUN_DIR=/var/run/apache2
ARG APACHE_LOCK_DIR=/var/lock/apache2

# PECL Modules
RUN pecl -q install apcu \
  imagick \
  memcached \
  redis > /dev/null

# Adjusting freetype message error
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp

# PHP Extensions needed
RUN docker-php-ext-install -j "$(nproc)" \
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
  zip

# More extensions
RUN docker-php-ext-enable \
  imagick \
  apcu \
  memcached \
  redis

# Enabling Modules
RUN a2enmod dir env headers mime rewrite setenvif deflate ssl

# Adjusting PHP settings
RUN { \
  echo 'opcache.interned_strings_buffer=32'; \
  echo 'opcache.memory_consumption=256'; \
  echo 'opcache.save_comments=1'; \
  echo 'opcache.revalidate_freq=60'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini;

RUN { \
  echo 'extension=apcu.so'; \
  echo 'apc.enable_cli=1'; \
  } > /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini;

RUN { \
  echo 'memory_limit = 2G'; \
  echo 'upload_max_filesize=30G'; \
  echo 'post_max_size=30G'; \
  echo 'max_execution_time=86400'; \
  echo 'max_input_time=86400'; \
  } > /usr/local/etc/php/conf.d/nce.ini;

# Update apache configuration for ServerName
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/servername.conf \
  && a2enconf servername

RUN sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf
RUN sed -i 's/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf

# Set permissions to allow non-root user to access necessary folders
RUN chmod -R 777 ${APACHE_RUN_DIR} ${APACHE_LOCK_DIR} ${APACHE_LOG_DIR} ${APACHE_DOCUMENT_ROOT}

# Should be no need to modify beyond this point, unless you need to patch something or add more apps
COPY --chown=root:root ./000-default.conf /etc/apache2/sites-available/
COPY --chown=root:root ./cron.sh /cron.sh

## ADD www-data to tty group
RUN usermod -a -G tty www-data

FROM php as nextcloud
ARG nc_download_url=https://download.nextcloud.com/.customers/server/28.0.3-20124648/nextcloud-28.0.3-enterprise.zip

## DONT ADD STUFF BETWEEN HERE
RUN wget -q ${nc_download_url} -O /tmp/nextcloud.zip && cd /tmp && unzip -qq /tmp/nextcloud.zip && cd /tmp/nextcloud \
  && mkdir -p /var/www/html/data && touch /var/www/html/data/.ocdata && mkdir /var/www/html/config \
  && cp -a /tmp/nextcloud/* /var/www/html && cp -a /tmp/nextcloud/.[^.]* /var/www/html \
  && chown -R www-data:root /var/www/html && chmod +x /var/www/html/occ && rm -rf /tmp/nextcloud
RUN php /var/www/html/occ integrity:check-core
## AND HERE, OR CODE INTEGRITY CHECK MIGHT FAIL, AND IMAGE WILL NOT BUILD

## VARIOUS PATCHES COMES HERE IF NEEDED
COPY ./s3nomulti.diff /var/www/html/s3nomulti.diff
RUN cd /var/www/html/ && patch -p 1 < s3nomulti.diff
COPY ./s3sdknomultipart-53ba30db9fcd168dd7a38fb9314e8775e19e33fe.diff /var/www/html/s3sdknomultipart-53ba30db9fcd168dd7a38fb9314e8775e19e33fe.diff
RUN cd /var/www/html/ && patch -p 1 < s3sdknomultipart-53ba30db9fcd168dd7a38fb9314e8775e19e33fe.diff
COPY ./34d460fc9e3514d52cfa88dcb63d4ba9.patch /var/www/html/34d460fc9e3514d52cfa88dcb63d4ba9.patch
RUN cd /var/www/html/ && patch -p 1 < 34d460fc9e3514d52cfa88dcb63d4ba9.patch


# CLEAN UP
RUN apt remove -y curl make npm patch && apt autoremove -y
RUN rm -rf /tmp/*.tar.* && chown -R www-data:root /var/www/html && rm -rf /var/lib/apt/lists/*
