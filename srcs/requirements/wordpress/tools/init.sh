#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/db_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

WP_PATH="/var/www/wordpress"
mkdir -p "$WP_PATH"

until nc -z mariadb 3306 2>/dev/null; do
    echo "Aguardando MariaDB..."
    sleep 2
done
echo "MariaDB pronto!"

# 2. Só instala se wp-config ainda não existe
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    wp core download --path="$WP_PATH" --allow-root

    wp config create \
        --path="$WP_PATH" \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="mariadb:3306" \
        --allow-root

    wp core install \
        --path="$WP_PATH" \
        --url="$WP_URL" \
        --title="$DOMAIN_NAME" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email \
        --allow-root

    wp user create \
        "$WP_USER" "$WP_USER_EMAIL" \
        --role=editor \
        --user_pass="$WP_USER_PASSWORD" \
        --path="$WP_PATH" \
        --allow-root

    chown -R www-data:www-data "$WP_PATH"
fi

exec php-fpm8.2 -F