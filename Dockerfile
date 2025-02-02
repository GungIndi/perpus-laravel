# Use PHP image with PHP-FPM
FROM php:7.2-fpm

# Install required PHP extensions
RUN apt-get update && apt-get install -y \
    nano \
    nginx \
    git \
    unzip \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    zip \
    libzip-dev \
    default-mysql-client \
    && docker-php-ext-configure gd \
    && docker-php-ext-install gd pdo pdo_mysql zip

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set working directory
WORKDIR /var/www
COPY . /var/www
COPY .env.example /var/www/.env
RUN chown -R www-data:www-data /var/www && \
    find /var/www/ -type d -exec chmod 755 {} \; && \
    find /var/www/ -type f -exec chmod 755 {} \; && \
    chmod -R 775 storage bootstrap/cache

RUN chmod 600 -R config/

# Install dependencies
RUN composer update

EXPOSE 9000

COPY config/default.conf /etc/nginx/sites-available/default
COPY start.sh /start.sh
COPY wait-for-db.sh /wait-for-db.sh
RUN chmod 755 /start.sh /wait-for-db.sh

ENTRYPOINT ["/start.sh"]