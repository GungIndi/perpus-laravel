#!/bin/bash

# Ensure storage and cache directories are writable
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache
chmod -R 775 /var/www/storage /var/www/bootstrap/cache

# Wait for the database to be ready
./wait-for-db.sh db php artisan migrate --force

# Run Laravel commands
php artisan key:generate
php artisan db:seed
php artisan optimize
php artisan config:cache
php artisan route:clear
php artisan route:cache
php artisan view:clear
php artisan view:cache

# Start Nginx and PHP-FPM
service nginx start 
php-fpm