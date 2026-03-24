#!/bin/bash
set -e

# Lê as senhas dos Docker Secrets
DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/db_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

WP_PATH="/var/www/html"

# Cria o diretório se não existir
mkdir -p "$WP_PATH"

# Só instala o WordPress se ainda não foi instalado
if [ ! -f "$WP_PATH/wp-config.php" ]; then

    # Baixa o WordPress
    wp core download --path="$WP_PATH" --allow-root

    # Cria o wp-config.php com as configurações do banco
    wp config create \
        --path="$WP_PATH" \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="mariadb:3306" \
        --allow-root

    # Aguarda o MariaDB estar pronto (ele pode demorar para iniciar)
    until wp db check --path="$WP_PATH" --allow-root 2>/dev/null; do
        echo "Aguardando MariaDB..."
        sleep 2
    done

    # Instala o WordPress (cria as tabelas no banco)
    wp core install \
        --path="$WP_PATH" \
        --url="$WP_URL" \
        --title="$DOMAIN_NAME" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --allow-root

    # Cria um segundo usuário (não-admin)
    wp user create \
        "$WP_USER" "$WP_USER_EMAIL" \
        --role=editor \
        --user_pass="$WP_USER_PASSWORD" \
        --path="$WP_PATH" \
        --allow-root

    # Ajusta permissões
    chown -R www-data:www-data "$WP_PATH"
fi

# Inicia o PHP-FPM em foreground (não como daemon)
# O "-F" mantém o processo rodando no terminal — obrigatório em containers
exec php-fpm8.2 -F