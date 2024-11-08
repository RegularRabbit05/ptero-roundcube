FROM php:8.1-fpm-alpine
LABEL maintainer="Thomas Bruederli <thomas@roundcube.net>"
LABEL org.opencontainers.image.source="https://github.com/roundcube/roundcubemail-docker"

RUN set -ex; \
	if [ "fpm-alpine" = "apache" ]; then a2enmod rewrite; fi; \
	\
	apk add --no-cache \
		bash \
		coreutils \
		rsync \
		tzdata \
		aspell \
		aspell-en \
		unzip

RUN set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		icu-dev \
		freetype-dev \
		imagemagick-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libzip-dev \
		libtool \
		openldap-dev \
		postgresql-dev \
		sqlite-dev \
		aspell-dev \
	; \
	\
# Extract sources to avoid using pecl (https://github.com/docker-library/php/issues/374#issuecomment-690698974)
	pecl bundle -d /usr/src/php/ext imagick; \
	pecl bundle -d /usr/src/php/ext redis; \
	docker-php-ext-configure gd --with-jpeg --with-freetype; \
	docker-php-ext-configure ldap; \
	docker-php-ext-install \
		exif \
		gd \
		intl \
		ldap \
		pdo_mysql \
		pdo_pgsql \
		pdo_sqlite \
		zip \
		pspell \
		imagick \
		redis \
	; \
	docker-php-ext-enable imagick opcache redis; \
	docker-php-source delete; \
# Header files ".h"
	rm -r /usr/local/include/php/ext; \
	rm -r /tmp/pear; \
# Display installed modules
	php -m; \
	\
	extdir="$(php -r 'echo ini_get("extension_dir");')"; \
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive $extdir \
		| tr ',' '\n' \
		| sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
		)"; \
	apk add --virtual .roundcubemail-phpext-rundeps imagemagick $runDeps; \
	apk del .build-deps; \
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ] || (echo "Sanity check failed: php returned errors; $err"; exit 1;); \
# include the wait-for-it.sh script (latest commit)
	curl -fL https://raw.githubusercontent.com/vishnubob/wait-for-it/81b1373f17855a4dc21156cfe1694c31d7d1792e/wait-for-it.sh -o /wait-for-it.sh; \
	chmod +x /wait-for-it.sh;

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# use custom PHP settings
COPY php.ini /usr/local/etc/php/conf.d/roundcube-defaults.ini

# Define Roundcubemail version
ENV ROUNDCUBEMAIL_VERSION 1.6.9

# Define the GPG key used for the bundle verification process
ENV ROUNDCUBEMAIL_KEYID "F3E4 C04B B3DB 5D42 15C4  5F7F 5AB2 BAA1 41C4 F7D5"

# Download package and extract to web volume
RUN set -ex; \
	apk add --no-cache --virtual .fetch-deps \
		gnupg \
	; \
	\
	curl -o roundcubemail.tar.gz -fSL https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBEMAIL_VERSION}/roundcubemail-${ROUNDCUBEMAIL_VERSION}-complete.tar.gz; \
	curl -o roundcubemail.tar.gz.asc -fSL https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBEMAIL_VERSION}/roundcubemail-${ROUNDCUBEMAIL_VERSION}-complete.tar.gz.asc; \
	export GNUPGHOME="$(mktemp -d)"; \
	curl -fSL https://roundcube.net/download/pubkey.asc -o /tmp/pubkey.asc; \
	LC_ALL=C.UTF-8 gpg -n --show-keys --with-fingerprint --keyid-format=long /tmp/pubkey.asc | if [ $(grep -c -o 'Key fingerprint') != 1 ]; then echo 'The key file should contain only one GPG key'; exit 1; fi; \
	LC_ALL=C.UTF-8 gpg -n --show-keys --with-fingerprint --keyid-format=long /tmp/pubkey.asc | if [ $(grep -c -o "${ROUNDCUBEMAIL_KEYID}") != 1 ]; then echo 'The key ID should be the roundcube one'; exit 1; fi; \
	gpg --batch --import /tmp/pubkey.asc; \
	rm /tmp/pubkey.asc; \
	gpg --batch --verify roundcubemail.tar.gz.asc roundcubemail.tar.gz; \
	gpgconf --kill all; \
	mkdir /usr/src/roundcubemail; \
	tar -xf roundcubemail.tar.gz -C /usr/src/roundcubemail --strip-components=1 --no-same-owner; \
	rm -r "$GNUPGHOME" roundcubemail.tar.gz.asc roundcubemail.tar.gz; \
	rm -rf /usr/src/roundcubemail/installer; \
	chown -R www-data:www-data /usr/src/roundcubemail/logs; \
	apk del .fetch-deps; \
# Create the config dir
	mkdir -p /var/roundcube/config


RUN adduser -D -h /home/container container
RUN adduser container wheel
USER container
ENV  USER=container HOME=/home/container
WORKDIR /home/container

COPY --chmod=0755 entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
