#!/bin/bash

# Script de Restore MySQL
# Uso: ./mysql_restore.sh <caminho_arquivo_config>

set -e  # Sair em caso de erro
set -o pipefail  # Falhar se qualquer comando no pipe falhar

# Por padrao, log sem timestamp. Pode ser sobrescrito pelo arquivo de configuração.
log_timestamp=false

# Função para exibir mensagens de log com timestamp
log_message() {
    if [ "$log_timestamp" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    else
        echo "$1"
    fi
}

# Função para exibir uso do script
show_usage() {
    echo "Uso: $(basename "$0") <caminho_arquivo_config>"
    echo ""
    echo "O arquivo de configuração deve conter as seguintes variáveis:"
    echo "ssh_user=seu_usuario_ssh # (opcional)"
    echo "ssh_host=seu_host_ssh_ou_alias"
    echo "ssh_port=22 # (opcional)"
    echo "remote_backup_dir=/caminho/para/backups"
    echo "local_tmp_dir=/caminho/tmp # (opcional; padrao: \$TMPDIR/mysql_dumps)"
    echo "mysql_user=seu_usuario_mysql # (opcional; padrao: root)"
    echo "mysql_password=sua_senha_mysql # (opcional; pode ser vazio)"
    echo "mysql_host=seu_host_mysql # (opcional; padrao: localhost)"
    echo "target_db=nome_da_base_local"
    echo "post_restore_inline_script='SQL; SQL;' # (opcional)"
    echo "post_restore_file_script=/caminho/arquivo.sql # (opcional)"
    echo "log_timestamp=true # (opcional; padrão: false)"
    exit 1
}

# Limpeza em caso de interrupção
cleanup() {
    if [ -n "$local_backup_filepath" ] && [ -f "$local_backup_filepath" ] && [ "${keep_backup:-false}" = "false" ]; then
        log_message "Removendo arquivo temporário: $(basename "$local_backup_filepath")"
        rm -f "$local_backup_filepath"
    fi
}
trap cleanup EXIT INT TERM

# Verificar se o arquivo de configuração foi fornecido
if [ "$#" -ne 1 ]; then
    log_message "ERRO: Número incorreto de parâmetros."
    show_usage
fi

CONFIG_FILE="$1"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [[ "$CONFIG_FILE" != /* ]]; then
    CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
fi
CONFIG_DIR=$(dirname "$CONFIG_FILE")

# Verificar se o arquivo de configuração existe
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERRO: Arquivo de configuração '$CONFIG_FILE' não encontrado."
    exit 1
fi

# Carregar configurações
log_message "Carregando configurações de: $1"
source "$CONFIG_FILE"

# Verificar se todas as variáveis necessárias estão definidas
required_vars=(
    "ssh_host"
    "remote_backup_dir"
    "target_db"
)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_message "ERRO: Variável '$var' não está definida no arquivo de configuração."
        exit 1
    fi
done

# Defaults opcionais
tmp_base="${TMPDIR:-/tmp}"
local_tmp_dir="${local_tmp_dir:-$tmp_base/mysql_dumps}"
mysql_user="${mysql_user:-root}"
mysql_password="${mysql_password:-}"
mysql_host="${mysql_host:-localhost}"

# Criar diretório temporário local se não existir
if [ ! -d "$local_tmp_dir" ]; then
    log_message "Criando diretório temporário local: $local_tmp_dir"
    mkdir -p "$local_tmp_dir"
fi

SSH_OPTS=()
if [ -n "$ssh_port" ]; then
    SSH_OPTS=(-p "$ssh_port")
fi

ssh_target="$ssh_host"
if [ -n "$ssh_user" ]; then
    ssh_target="$ssh_user@$ssh_host"
fi

log_message "Buscando último backup remoto em: $ssh_target:$remote_backup_dir"
remote_latest_filepath=$(ssh "${SSH_OPTS[@]}" "$ssh_target" \
    "ls -1t \"$remote_backup_dir\"/*.sql.bz2 \"$remote_backup_dir\"/*.sql.gz 2>/dev/null | head -n 1")

if [ -z "$remote_latest_filepath" ]; then
    log_message "ERRO: Nenhum backup encontrado em '$remote_backup_dir'."
    exit 1
fi

local_backup_filename=$(basename "$remote_latest_filepath")
local_backup_filepath="$local_tmp_dir/$local_backup_filename"

log_message "Copiando backup remoto: $local_backup_filename"
rsync_ssh="ssh"
if [ -n "$ssh_port" ]; then
    rsync_ssh="ssh -p $ssh_port"
fi
rsync -a -e "$rsync_ssh" "$ssh_target:$remote_latest_filepath" "$local_backup_filepath"

if [ ! -s "$local_backup_filepath" ]; then
    log_message "ERRO: Falha ao copiar o backup ou arquivo vazio."
    exit 1
fi
keep_backup=true

# Usar MYSQL_PWD para evitar exposição da senha no ps aux
mysql_cmd=(mysql -h "$mysql_host" -u "$mysql_user")
export MYSQL_PWD="$mysql_password"

log_message "Criando base local (se necessário): $target_db"
"${mysql_cmd[@]}" -e "CREATE DATABASE IF NOT EXISTS \`$target_db\`;"

log_message "Restaurando backup em: $target_db"
case "$local_backup_filepath" in
    *.sql.bz2)
        bzip2 -dc "$local_backup_filepath" | "${mysql_cmd[@]}" "$target_db"
        ;;
    *.sql.gz)
        gzip -dc "$local_backup_filepath" | "${mysql_cmd[@]}" "$target_db"
        ;;
    *)
        log_message "ERRO: Extensao de backup nao suportada: $(basename "$local_backup_filepath")"
        exit 1
        ;;
esac

if [ -n "$post_restore_inline_script" ]; then
    log_message "Executando script SQL inline..."
    "${mysql_cmd[@]}" "$target_db" -e "$post_restore_inline_script"
fi

if [ -n "$post_restore_file_script" ]; then
    script_path="$post_restore_file_script"
    if [[ "$script_path" != /* ]]; then
        script_path="$CONFIG_DIR/$script_path"
    fi
    if [ ! -f "$script_path" ]; then
        log_message "ERRO: Arquivo SQL nao encontrado: $script_path"
        exit 1
    fi
    log_message "Executando script SQL de arquivo: $(basename "$script_path")"
    "${mysql_cmd[@]}" "$target_db" < "$script_path"
fi

log_message "Limpando dumps antigos (mais de 7 dias)..."
find "$local_tmp_dir" -maxdepth 1 -type f \( -name "*.sql.bz2" -o -name "*.sql.gz" \) -mtime +7 -print0 | \
while IFS= read -r -d '' old_dump; do
    log_message "Removendo dump antigo: $(basename "$old_dump")"
    rm -f "$old_dump"
done

final_dump_count=$(find "$local_tmp_dir" -maxdepth 1 -type f \( -name "*.sql.bz2" -o -name "*.sql.gz" \) | wc -l | tr -d ' ')
total_size=$(du -sh "$local_tmp_dir" | cut -f1)

log_message "Restore concluído com sucesso!"
log_message "Total de dumps mantidos: $final_dump_count"
log_message "Espaço total dos dumps: $total_size"
