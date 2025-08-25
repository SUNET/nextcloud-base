FROM debian:trixie-slim as build

ENV nc_download_url=https://download.nextcloud.com/.customers/server/30.0.14-a2d2b3b6/nextcloud-30.0.14-enterprise.zip
ENV php_version=8.3

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
# Install dependencies
RUN { \
      apt-get -q update > /dev/null && apt-get -q install -y \
      apt-transport-https \
      ca-certificates\
      curl\
      gnupg2 \
      lsb-release \
      > /dev/null; \
      curl -sSL https://packages.sury.org/php/README.txt | bash -x; \
      apt-get -q update > /dev/null && apt-get install -y \
      apache2 \
      ffmpeg \
      libapache2-mod-php${php_version} \
      mariadb-client \
      npm \
      patch \
      php${php_version} \
      php${php_version}-apcu \
      php${php_version}-ctype \
      php${php_version}-curl \
      php${php_version}-dom \
      php${php_version}-exif \
      php${php_version}-gd \
      php${php_version}-gmp \
      php${php_version}-imagick \
      php${php_version}-intl \
      php${php_version}-mbstring \
      php${php_version}-memcached \
      php${php_version}-mysql \
      php${php_version}-sqlite3 \
      php${php_version}-phpdbg \
      php${php_version}-posix \
      php${php_version}-redis \
      php${php_version}-xml \
      php${php_version}-zip \
      redis-tools \
      ssl-cert \
      unzip \
      vim \
      wget \
      > /dev/null; \
      update-alternatives --set php /usr/bin/php${php_version}; \
      update-alternatives --set phpdbg /usr/bin/phpdbg${php_version}; \
      phpenmod apcu ctype curl dom fileinfo gd mbstring memcached posix redis simplexml xml xmlreader xmlwriter zip; \
      a2enmod dir env headers mime rewrite setenvif deflate ssl; \
      echo "ServerName localhost" | tee /etc/apache2/conf-available/servername.conf \
      && a2enconf servername; \
      sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf; \
      sed -i 's/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
    }
RUN wget -q https://downloads.rclone.org/rclone-current-linux-amd64.deb \
  && dpkg -i ./rclone-current-linux-amd64.deb 
## DONT ADD STUFF BETWEEN HERE
RUN wget -q ${nc_download_url} -O /tmp/nextcloud.zip && cd /tmp && unzip -qq /tmp/nextcloud.zip && cd /tmp/nextcloud \
  && mkdir -p /var/www/html/data && echo '# Nextcloud data directory' > /var/www/html/data/.ncdata && mkdir /var/www/html/config \
  && cp -a /tmp/nextcloud/* /var/www/html && cp -a /tmp/nextcloud/.[^.]* /var/www/html \
  && chown -R www-data:root /var/www/html && chmod +x /var/www/html/occ \
  && rm -rf ./rclone-current-linux-amd64.deb /tmp/nextcloud \
  /tmp/newcloud.zip /var/www/html/nextcloud.zip
#RUN su - www-data -s /bin/bash -c "/var/www/html/occ integrity:check-core"
## AND HERE, OR CODE INTEGRITY CHECK MIGHT FAIL, AND IMAGE WILL NOT BUILD

# Copy over files
COPY --chown=root:root ./000-default.conf /etc/apache2/sites-available/
COPY --chown=root:root ./cron.sh /cron.sh
COPY --chown=www-data:root ./htaccess /var/www/html/.htaccess
copy --chown=www-data:root ./apache.php.ini /etc/php/${php_version}/apache2/php.ini
copy --chown=www-data:root ./apcu.ini /etc/php/${php_version}/mods-available/apcu.ini
copy --chown=www-data:root ./cli.php.ini /etc/php/${php_version}/cli/php.ini
copy --chown=www-data:root ./nce.ini /etc/php/${php_version}/apache2/conf.d/nce.ini
copy --chown=www-data:root ./opcache-recommended.ini /etc/php/${php_version}/apache2/conf.d/opcache-recommended.ini

## ADD www-data to tty group
RUN usermod -a -G tty www-data
