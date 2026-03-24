FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    php8.2-fpm \
    php8.2-mysql \
    php8.2-curl \
    php8.2-gd \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Baixa o wp-cli — ferramenta de linha de comando do WordPress
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 9000

ENTRYPOINT ["/init.sh"]