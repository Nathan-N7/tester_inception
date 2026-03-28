#!/bin/bash

# Cores
G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
B='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { echo -e "${G}[OK]${NC}    $1";    ((PASS++)); }
fail() { echo -e "${R}[FALHA]${NC} $1"; ((FAIL++)); }
warn() { echo -e "${Y}[AVISO]${NC} $1"; }

echo -e "${B}====================================================${NC}"
echo -e "${B}      ULTIMATE INCEPTION CHECKER - 42 EVALUATION    ${NC}"
echo -e "${B}====================================================${NC}\n"

# Carregar variáveis do .env
if [ -f "srcs/.env" ]; then
    export $(grep -v '^#' srcs/.env | xargs)
    USER_LOGIN=${DOMAIN_NAME%%.*}
    USER_LOGIN=${USER_LOGIN:-$USER}
else
    echo -e "${R}[ERRO FATAL] srcs/.env não encontrado. Abortando.${NC}"
    exit 1
fi

DOMAIN="${USER_LOGIN}.42.fr"

# ============================================================
# FASE 1: CHECAGEM ESTÁTICA DE ARQUIVOS
# ============================================================
echo -e "${Y}>>> FASE 1: CHECAGEM ESTÁTICA DE ARQUIVOS <<<${NC}"

check_file()   { if [ -f "$1" ]; then ok "$1 encontrado."; else fail "$1 faltando."; fi; }
check_string() { grep -r "$1" srcs/ > /dev/null 2>&1 && fail "Proibido: '$1' encontrado." || ok "Sem '$1'."; }

check_file "Makefile"
check_file "srcs/docker-compose.yml"
check_file "srcs/.env"

check_string "network: host"
check_string "links:"
check_string "tail -f"
check_string "sleep infinity"

# Imagens base: apenas Debian ou Alpine
INVALID_BASE=$(grep -r "^FROM" srcs/ 2>/dev/null | grep -viE "debian|alpine")
if [ -n "$INVALID_BASE" ]; then
    fail "Imagem base que não é Debian ou Alpine encontrada:\n  $INVALID_BASE"
else
    ok "Todos os Dockerfiles usam Debian ou Alpine."
fi

# Tag :latest proibida
if grep -r "^FROM" srcs/ 2>/dev/null | grep -q ":latest"; then
    fail "Tag ':latest' encontrada nos Dockerfiles — proibida pelo subject."
else
    ok "Sem uso de ':latest' nos Dockerfiles."
fi

# Senhas não podem estar hardcoded no compose ou Dockerfiles
for secret_kw in "MYSQL_PASSWORD" "MYSQL_ROOT_PASSWORD" "WP_ADMIN_PASSWORD"; do
    if grep -r "${secret_kw}=." srcs/docker-compose.yml 2>/dev/null | grep -qv '^\s*#'; then
        fail "Senha hardcoded detectada no docker-compose.yml: $secret_kw"
    else
        ok "Sem senha hardcoded para $secret_kw no compose."
    fi
done

# ENTRYPOINT ou CMD em cada Dockerfile
for dockerfile in $(find srcs/ -name "Dockerfile" 2>/dev/null); do
    if grep -qE "^ENTRYPOINT|^CMD" "$dockerfile"; then
        ok "$dockerfile tem ENTRYPOINT/CMD definido."
    else
        fail "$dockerfile sem ENTRYPOINT/CMD — container não sabe o que executar."
    fi
done

# Política de restart
if grep -q "restart:" srcs/docker-compose.yml 2>/dev/null; then
    ok "Política de restart configurada no docker-compose."
else
    fail "Nenhum 'restart:' encontrado no docker-compose.yml."
fi

# Verificar secrets no compose (boa prática, não usar env puro para senhas)
if grep -q "secrets:" srcs/docker-compose.yml 2>/dev/null; then
    ok "Uso de Docker secrets detectado no compose."
else
    warn "Nenhum Docker secret detectado — senhas sendo passadas via env puro?"
fi

# ============================================================
# FASE 2: LIMPEZA E BUILD
# ============================================================
echo -e "\n${Y}>>> FASE 2: LIMPEZA E MAKE <<<${NC}"
echo "Executando limpeza completa..."
docker stop $(docker ps -qa) > /dev/null 2>&1
docker rm $(docker ps -qa) > /dev/null 2>&1
docker rmi -f $(docker images -qa) > /dev/null 2>&1
docker volume rm $(docker volume ls -q) > /dev/null 2>&1
docker network rm $(docker network ls -q) > /dev/null 2>&1

echo "Rodando 'make' (pode demorar)..."
make > /dev/null 2>&1
if [ $? -eq 0 ]; then
    ok "make executado sem erros."
else
    fail "make retornou erro."
fi

echo "Aguardando containers estabilizarem (20s)..."
sleep 20

# ============================================================
# FASE 3: CONTAINERS E IMAGENS
# ============================================================
echo -e "\n${Y}>>> FASE 3: CONTAINERS E NOMENCLATURA <<<${NC}"
EXPECTED_SERVICES=("nginx" "wordpress" "mariadb")

for service in "${EXPECTED_SERVICES[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        ok "Container '$service' está rodando."
    else
        fail "Container '$service' NÃO está rodando."
    fi

    if docker images --format '{{.Repository}}' | grep -q "^${service}$"; then
        ok "Imagem '$service' existe com nome correto."
    else
        fail "Imagem '$service' não encontrada (nome deve ser igual ao serviço)."
    fi
done

# Verificar que não há containers extras além dos 3 obrigatórios
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' | wc -l)
if [ "$RUNNING_CONTAINERS" -eq 3 ]; then
    ok "Exatamente 3 containers rodando."
else
    warn "$RUNNING_CONTAINERS containers rodando (esperado: 3 obrigatórios + possíveis bônus)."
fi

# ============================================================
# FASE 4: REDES E VOLUMES
# ============================================================
echo -e "\n${Y}>>> FASE 4: REDES E VOLUMES <<<${NC}"

# Rede
if docker network ls | grep -qE "inception|srcs"; then
    ok "Rede docker do projeto encontrada."
else
    fail "Nenhuma rede do projeto encontrada."
fi

# Verificar que containers estão na mesma rede customizada (não default bridge)
for service in "${EXPECTED_SERVICES[@]}"; do
    NET=$(docker inspect "$service" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)
    if echo "$NET" | grep -qE "inception|srcs"; then
        ok "Container '$service' está na rede customizada ($NET)."
    else
        fail "Container '$service' não está na rede customizada do projeto."
    fi
done

# Volumes — verifica se o device (bind mount) aponta para /home/<login>/data/
# Nota: com bind mount, o Mountpoint no inspect permanece em /var/lib/docker/volumes/...
# O caminho real fica em Options.device — é isso que o subject exige.
for vol in $(docker volume ls -q | grep -E "srcs|inception"); do
    DEVICE=$(docker volume inspect "$vol" --format '{{index .Options "device"}}')
    DRIVER=$(docker volume inspect "$vol" --format '{{.Driver}}')
    O_OPT=$(docker volume inspect "$vol" --format '{{index .Options "o"}}')
    if echo "$DEVICE" | grep -q "/home/${USER_LOGIN}/data"; then
        ok "Volume $vol com bind mount correto: $DEVICE"
    elif [ -z "$DEVICE" ]; then
        fail "Volume $vol sem bind mount configurado (driver_opts ausente no compose)."
    else
        fail "Volume $vol com device errado: $DEVICE (Esperado: /home/${USER_LOGIN}/data/...)"
    fi
    # Garantir que é bind mount (type=none, o=bind)
    if [ "$O_OPT" == "bind" ]; then
        ok "Volume $vol configurado como bind mount (o=bind)."
    else
        fail "Volume $vol não está configurado como bind mount (o=$O_OPT)."
    fi
done

# Verificar que os diretórios de dados existem
for dir in "db" "wordpress"; do
    if [ -d "/home/${USER_LOGIN}/data/${dir}" ]; then
        ok "Diretório /home/${USER_LOGIN}/data/${dir} existe."
    else
        fail "Diretório /home/${USER_LOGIN}/data/${dir} não encontrado."
    fi
done

# ============================================================
# FASE 5: NGINX E TLS
# ============================================================
echo -e "\n${Y}>>> FASE 5: TESTES DE REDE (NGINX E TLS) <<<${NC}"

# Porta 80 deve estar fechada ou redirecionar
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$DOMAIN 2>/dev/null)
if [ "$HTTP_CODE" == "000" ] || [ "$HTTP_CODE" == "301" ]; then
    ok "Porta 80 bloqueada ou redirecionando (HTTP $HTTP_CODE)."
else
    fail "NGINX respondendo indevidamente na porta 80 (HTTP $HTTP_CODE)."
fi

# Porta 443 deve responder
HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 https://$DOMAIN 2>/dev/null)
if [ "$HTTPS_CODE" == "200" ] || [ "$HTTPS_CODE" == "301" ] || [ "$HTTPS_CODE" == "302" ]; then
    ok "Porta 443 (HTTPS) respondendo corretamente (HTTP $HTTPS_CODE)."
else
    fail "Porta 443 falhou (HTTP $HTTPS_CODE)."
fi

# TLS 1.2
if echo "Q" | openssl s_client -connect $DOMAIN:443 -tls1_2 -servername $DOMAIN > /dev/null 2>&1; then
    ok "TLSv1.2 ativo e funcionando."
else
    warn "TLSv1.2 não suportado (ok se TLSv1.3 estiver ativo)."
fi

# TLS 1.3
if echo "Q" | openssl s_client -connect $DOMAIN:443 -tls1_3 -servername $DOMAIN > /dev/null 2>&1; then
    ok "TLSv1.3 ativo e funcionando."
else
    warn "TLSv1.3 não suportado (ok se TLSv1.2 estiver ativo)."
fi

# TLS 1.0 deve estar DESABILITADO
if echo "Q" | openssl s_client -connect $DOMAIN:443 -tls1 -servername $DOMAIN > /dev/null 2>&1; then
    fail "TLSv1.0 está habilitado — deve ser desabilitado pelo subject."
else
    ok "TLSv1.0 desabilitado corretamente."
fi

# TLS 1.1 deve estar DESABILITADO
if echo "Q" | openssl s_client -connect $DOMAIN:443 -tls1_1 -servername $DOMAIN > /dev/null 2>&1; then
    fail "TLSv1.1 está habilitado — deve ser desabilitado pelo subject."
else
    ok "TLSv1.1 desabilitado corretamente."
fi

# Apenas porta 443 exposta
PORTS=$(docker inspect nginx --format '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} {{end}}' 2>/dev/null)
if echo "$PORTS" | grep -q "443/tcp" && ! echo "$PORTS" | grep -q "80/tcp"; then
    ok "NGINX expõe apenas a porta 443."
else
    warn "Portas expostas pelo NGINX: $PORTS — verifique se apenas 443 está exposta."
fi

# ============================================================
# FASE 6: MARIADB
# ============================================================
echo -e "\n${Y}>>> FASE 6: BANCO DE DADOS <<<${NC}"
DB_CONTAINER=$(docker ps -qf "name=mariadb")

if [ -n "$DB_CONTAINER" ]; then
    # Ler senha do secret dentro do container (Docker secrets ficam em /run/secrets/)
    DB_PASS=$(docker exec $DB_CONTAINER cat /run/secrets/db_password 2>/dev/null)

    # Fallback: tentar variável de ambiente do .env
    if [ -z "$DB_PASS" ]; then
        DB_PASS="$MYSQL_PASSWORD"
    fi

    if docker exec $DB_CONTAINER mysql -u"$MYSQL_USER" -p"${DB_PASS}" "$MYSQL_DATABASE" -e "SHOW TABLES;" > /dev/null 2>&1; then
        ok "Conexão com MariaDB bem-sucedida (usuário: $MYSQL_USER)."
        TABLE_COUNT=$(docker exec $DB_CONTAINER mysql -u"$MYSQL_USER" -p"${DB_PASS}" "$MYSQL_DATABASE" \
            -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE';" 2>/dev/null)
        if [ "$TABLE_COUNT" -gt 0 ] 2>/dev/null; then
            ok "Banco '$MYSQL_DATABASE' populado com $TABLE_COUNT tabelas."
        else
            fail "Banco '$MYSQL_DATABASE' está vazio — WordPress instalado corretamente?"
        fi
    else
        fail "Falha ao conectar no DB com usuário '$MYSQL_USER' — verifique secret e inicialização."
    fi

    # Root não deve ter senha vazia
    if docker exec $DB_CONTAINER mysql -uroot -e "SHOW DATABASES;" > /dev/null 2>&1; then
        fail "Root do MariaDB sem senha — vulnerabilidade de segurança!"
    else
        ok "Root do MariaDB protegido com senha."
    fi
else
    fail "Container MariaDB não encontrado para teste."
fi

# ============================================================
# FASE 7: WORDPRESS
# ============================================================
echo -e "\n${Y}>>> FASE 7: WORDPRESS <<<${NC}"
DB_CONTAINER=$(docker ps -qf "name=mariadb")

if [ -n "$DB_CONTAINER" ]; then
    DB_PASS=$(docker exec $DB_CONTAINER cat /run/secrets/db_password 2>/dev/null)
    if [ -z "$DB_PASS" ]; then DB_PASS="$MYSQL_PASSWORD"; fi

    # Verificar número de usuários (subject exige ao menos 2: admin + outro)
    USER_COUNT=$(docker exec $DB_CONTAINER mysql -u"$MYSQL_USER" -p"${DB_PASS}" "$MYSQL_DATABASE" \
        -se "SELECT COUNT(*) FROM wp_users;" 2>/dev/null)
    if [ "$USER_COUNT" -ge 2 ] 2>/dev/null; then
        ok "WordPress tem $USER_COUNT usuários cadastrados (mínimo 2 exigido)."
    else
        fail "WordPress precisa ter ao menos 2 usuários (admin + outro sem 'admin' no nome)."
    fi

    # Admin não pode ter "admin" no username
    ADMIN_NAME=$(docker exec $DB_CONTAINER mysql -u"$MYSQL_USER" -p"${DB_PASS}" "$MYSQL_DATABASE" \
        -se "SELECT user_login FROM wp_users WHERE ID=1;" 2>/dev/null)
    if echo "$ADMIN_NAME" | grep -iq "^admin$"; then
        fail "Username do admin é 'admin' — proibido pelo subject."
    else
        ok "Username do admin não é 'admin' (é: $ADMIN_NAME)."
    fi
fi

# WordPress acessível via HTTPS
WP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 https://$DOMAIN/wp-login.php 2>/dev/null)
if [ "$WP_CODE" == "200" ]; then
    ok "WordPress login page acessível via HTTPS."
else
    warn "wp-login.php retornou HTTP $WP_CODE — verifique se o WordPress está funcionando."
fi

# ============================================================
# RESUMO FINAL
# ============================================================
echo -e "\n${B}====================================================${NC}"
echo -e "${B}                   RESUMO FINAL                     ${NC}"
echo -e "${B}====================================================${NC}"
echo -e "${G}Passou: $PASS${NC}"
echo -e "${R}Falhou: $FAIL${NC}"
TOTAL=$((PASS + FAIL))
SCORE=$(echo "scale=1; $PASS * 100 / $TOTAL" | bc)
echo -e "${Y}Score estimado: ${SCORE}%${NC}"
echo -e "${B}====================================================${NC}"