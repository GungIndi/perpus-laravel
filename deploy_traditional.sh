#!/bin/bash
set -e

# ##################################################################
# TRADITIONAL DEPLOYMENT SCRIPT FOR PERPUS-LARAVEL (LEMP STACK)
#
# REQUIREMENTS:
#   - A fresh Debian/Ubuntu VPS.
#   - A Git repository for your project.
#   - DNS pointing your domain to the VPS IP address.
#
# USAGE:
#   1. Edit the CONFIGURATION variables below.
#   2. Make the script executable: chmod +x deploy_traditional.sh
#   3. Run with sudo: ./deploy_traditional.sh
# ##################################################################

# --- START CONFIGURATION ---

# Git repository URL of your Laravel project
REPO_URL="https://github.com/GungIndi/perpus-laravel.git"

# The directory to clone the project into
PROJECT_DIR="/var/www/perpus-laravel"

# Domain name for the application
APP_DOMAIN="_"

# Database credentials
DB_NAME="perpus_db"
DB_USER="perpus_user"
DB_PASSWORD="perpus_pass"

# The PHP version to install
PHP_VERSION="7.4"

# --- END CONFIGURATION ---

# --- SCRIPT LOGIC ---

echo "🚀 Starting traditional LEMP stack deployment for perpus-laravel..."

# 1. Install System Dependencies
# ------------------------------
echo "Updating package lists..."
apt-get update -y

echo "Installing system dependencies: Nginx, MySQL, Git, Unzip..."
# The -y flag assumes "yes" to all prompts
apt-get install -y nginx mariadb-server git unzip curl software-properties-common

# Add the repository for modern PHP versions on Debian (sury.org)
echo "Adding deb.sury.org repository for PHP on Debian..."

# First, clean up any old, conflicting PPA repositories from previous attempts
echo "Cleaning up old Ondrej PPA files to prevent conflicts..."
rm -f /etc/apt/sources.list.d/ondrej-*.list
rm -f /etc/apt/keyrings/ondrej-*.gpg

# Install prerequisites for adding custom repositories
apt-get install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg

# Import the GPG key for the repository
KEYRING_PATH="/etc/apt/keyrings/sury-php.gpg"
curl -sSLo /tmp/sury.key https://packages.sury.org/php/apt.gpg
gpg --dearmor -o "$KEYRING_PATH" /tmp/sury.key
rm /tmp/sury.key

# Create the repository source file. This will use the correct Debian codename (e.g., bullseye, bookworm)
SOURCE_LIST_PATH="/etc/apt/sources.list.d/sury-php.list"
echo "deb [signed-by=${KEYRING_PATH}] https://packages.sury.org/php/ $(lsb_release -sc) main" > "$SOURCE_LIST_PATH"

# Update package lists after adding the new repository
apt-get update -y

# Install PHP and required extensions
echo "Installing PHP ${PHP_VERSION} and extensions..."
apt-get install -y php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-bcmath php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd

# Install Composer
if ! [ -x "$(command -v composer)" ]; then
    echo "Installing Composer globally..."
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer is already installed."
fi

# Install Node.js and npm
if ! [ -x "$(command -v node)" ]; then
    echo "Installing Node.js and npm..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
else
    echo "Node.js is already installed."
fi

# 2. Configure MySQL
# --------------------
echo "Securing MySQL and creating application database..."
# Use a non-interactive method to create the database and user
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "Database '${DB_NAME}' and user '${DB_USER}' created."

# 3. Clone or Update Repository
# -----------------------------
echo "Cloning application repository from ${REPO_URL}..."
if [ -d "$PROJECT_DIR" ]; then
    echo "Project directory already exists. Skipping clone."
    cd "$PROJECT_DIR"
    git pull
else
    git clone "$REPO_URL" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

# 4. Install Application Dependencies
# -----------------------------------
echo "Installing Composer dependencies..."
composer install --no-interaction --no-dev --optimize-autoloader

echo "Installing NPM dependencies and building assets..."
npm install
npm run build # Assumes a 'build' script in package.json (e.g., for Vite or Mix)

# 5. Configure Laravel
# ----------------------
echo "Configuring Laravel .env file..."
if [ ! -f ".env" ]; then
    cp .env.example .env
fi

# Use sed to update the .env file
sed -i "s|^APP_URL=.*|APP_URL=http://${APP_DOMAIN}|" .env
sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env
sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env

echo "Generating application key..."
php artisan key:generate

# 6. Configure Nginx
# --------------------
echo "Configuring Nginx..."
# Create Nginx server block configuration
cat > /etc/nginx/sites-available/${APP_DOMAIN} <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};
    root ${PROJECT_DIR}/public;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable the new site and disable the default one
ln -s /etc/nginx/sites-available/${APP_DOMAIN} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "Testing and restarting Nginx..."
nginx -t
systemctl reload nginx

# 7. Set Permissions
# ------------------
echo "Setting directory permissions..."
# Set ownership to the web server user
chown -R www-data:www-data ${PROJECT_DIR}/storage ${PROJECT_DIR}/bootstrap/cache
# Set correct write permissions
chmod -R 775 ${PROJECT_DIR}/storage ${PROJECT_DIR}/bootstrap/cache

# 8. Finalize Application Setup
# -----------------------------
echo "Running database migrations and caching config..."
php artisan migrate --seed --force
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Deployment successful!"
echo "--------------------------"
echo "Your application should now be accessible at: http://${APP_DOMAIN}"
echo "MySQL User: ${DB_USER}"
echo "MySQL Password: ${DB_PASSWORD}"
echo "--------------------------"
