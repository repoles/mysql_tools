#!/bin/bash

# Script para enviar o primeiro backup do mês para S3
# Uso: ./mysql_s3_backup.sh <caminho_arquivo_config>

set -e
set -o pipefail

# Por padrao, log sem timestamp. Pode ser sobrescrito pelo arquivo de configuração.
log_timestamp=false

log_message() {
    if [ "$log_timestamp" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    else
        echo "$1"
    fi
}

show_usage() {
    echo "Uso: $(basename "$0") <caminho_arquivo_config>"
    echo ""
    echo "O arquivo de configuração deve conter as seguintes variáveis:"
    echo "db_name=nome_da_base"
    echo "backup_dir=/caminho/para/backup"
    echo "s3_dest=s3://bucket/pasta"
    echo "aws_cli_path=/caminho/para/aws # (opcional; padrão: /usr/local/bin)"
    echo "log_timestamp=true # (opcional; padrão: false)"
    exit 1
}

if [ "$#" -ne 1 ]; then
    log_message "ERRO: Número incorreto de parâmetros."
    show_usage
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERRO: Arquivo de configuração '$CONFIG_FILE' não encontrado."
    exit 1
fi

log_message "Carregando configurações de: $1"
source "$CONFIG_FILE"

if [ -z "$aws_cli_path" ]; then
    aws_cli_path="/usr/local/bin"
fi

if [ -x "$aws_cli_path" ] && [ "$(basename "$aws_cli_path")" = "aws" ]; then
    aws_cli="$aws_cli_path"
else
    aws_cli="${aws_cli_path%/}/aws"
fi

if [ ! -x "$aws_cli" ]; then
    log_message "ERRO: Executável do aws não encontrado ou sem permissão de execução: $aws_cli"
    exit 1
fi

required_vars=("backup_dir" "db_name" "s3_dest")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_message "ERRO: Variável '$var' não está definida no arquivo de configuração."
        exit 1
    fi
done

if [ ! -d "$backup_dir" ]; then
    log_message "ERRO: Diretório de backup '$backup_dir' não encontrado."
    exit 1
fi

current_month=$(date '+%Y-%m')
log_message "Procurando backups do mês: $current_month"

s3_prefix="${s3_dest%/}/"

# Se já existir algum backup deste mês no S3, não enviar outro
existing_month=$("$aws_cli" s3 ls "$s3_prefix" | awk '{print $4}' | \
    awk -v p="${db_name}_${current_month}-" 'index($0, p)==1 && $0 ~ /\.sql\.bz2$/ {print; exit}')

if [ -n "$existing_month" ]; then
    log_message "Já existe um backup deste mês no S3: $existing_month"
    log_message "Nenhuma ação necessária."
    exit 0
fi

shopt -s nullglob
files=("$backup_dir/${db_name}_${current_month}-"*.sql.bz2)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    log_message "Nenhum backup encontrado para o mês atual."
    exit 0
fi

# Como o padrão usa YYYY-MM-DD_HHhMMmSSs, a ordenação lexicográfica funciona.
earliest_file=$(printf '%s\n' "${files[@]}" | sort | head -n 1)

if [ ! -f "$earliest_file" ]; then
    log_message "ERRO: Arquivo selecionado não encontrado: $earliest_file"
    exit 1
fi

basename_file=$(basename "$earliest_file")
s3_target="${s3_prefix}${basename_file}"

log_message "Arquivo selecionado: $basename_file"
log_message "Destino S3: $s3_target"

if "$aws_cli" s3 ls "$s3_target" >/dev/null 2>&1; then
    log_message "Arquivo já existe no S3. Nenhuma ação necessária."
    exit 0
fi

log_message "Enviando arquivo para o S3..."
"$aws_cli" s3 cp "$earliest_file" "$s3_prefix"

log_message "Upload concluído com sucesso."
