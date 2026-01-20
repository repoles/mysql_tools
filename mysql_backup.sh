#!/bin/bash

# Script de Backup MySQL
# Uso: ./mysql_backup.sh <caminho_arquivo_config>

set -e  # Sair em caso de erro
set -o pipefail  # Falhar se qualquer comando no pipe falhar

# Por padrao, log com timestamp.
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
    echo "Uso: $(basename $0) <caminho_arquivo_config>"
    echo ""
    echo "O arquivo de configuração deve conter as seguintes variáveis:"
    echo "username=seu_usuario"
    echo "password=sua_senha # (pode ser vazio para usuários sem senha)"
    echo "host=seu_host"
    echo "backup_dir=/caminho/para/backup"
    echo "db_name=nome_da_base"
    exit 1
}

# Limpeza em caso de interrupção
cleanup() {
    if [ -f "$backup_filepath" ] && [ ! -s "$backup_filepath" ]; then
        log_message "Limpando arquivo temporário..."
        rm -f "$backup_filepath"
    fi
}
trap cleanup EXIT INT TERM

# Verificar se o arquivo de configuração foi fornecido
if [ $# -ne 1 ]; then
    log_message "ERRO: Número incorreto de parâmetros."
    show_usage
fi

CONFIG_FILE="$1"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [[ "$CONFIG_FILE" != /* ]]; then
    CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
fi

# Verificar se o arquivo de configuração existe
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERRO: Arquivo de configuração '$CONFIG_FILE' não encontrado."
    exit 1
fi

# Carregar configurações
log_message "Carregando configurações de: $1"
source "$CONFIG_FILE"

# Verificar se todas as variáveis necessárias estão definidas
# Nota: password pode ser vazia, então verificamos se ela está definida (não necessariamente com valor)
required_vars=("username" "host" "backup_dir" "db_name")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_message "ERRO: Variável '$var' não está definida no arquivo de configuração."
        exit 1
    fi
done

# Verificar se a variável password está definida (mesmo que vazia)
if ! grep -q "^password=" "$CONFIG_FILE"; then
    log_message "ERRO: Variável 'password' não está definida no arquivo de configuração."
    log_message "Dica: Para usuários sem senha, use: password="
    exit 1
fi

# Criar diretório de backup se não existir
if [ ! -d "$backup_dir" ]; then
    log_message "Criando diretório de backup: $backup_dir"
    mkdir -p "$backup_dir"
fi

# Verificar espaço disponível (opcional)
available_space=$(df "$backup_dir" | awk 'NR==2 {print $4}')
if [ "$available_space" -lt 1000000 ]; then  # Menos de ~1GB
    log_message "AVISO: Pouco espaço disponível no diretório de backup."
fi

# Gerar timestamp para o nome do arquivo
timestamp=$(date '+%Y-%m-%d_%Hh%Mm%Ss')
backup_filename="${db_name}_${timestamp}.sql.bz2"
backup_filepath="$backup_dir/$backup_filename"

log_message "Iniciando backup da base de dados: $db_name"
log_message "Arquivo de backup: $backup_filename"

# Realizar o dump da base de dados diretamente compactado
log_message "Realizando dump compactado diretamente..."

# Opções do mysqldump para backup completo
MYSQLDUMP_OPTIONS="--single-transaction"

# Usar diferentes comandos dependendo se há senha ou não
if [ -z "$password" ]; then
    # Usuário sem senha
    if mysqldump -h "$host" -u "$username" $MYSQLDUMP_OPTIONS "$db_name" | bzip2 > "$backup_filepath"; then
        log_message "Dump compactado realizado com sucesso."
    else
        log_message "ERRO: Falha ao realizar o dump compactado."
        [ -f "$backup_filepath" ] && rm -f "$backup_filepath"  # Limpar arquivo parcial
        exit 1
    fi
else
    # Usuário com senha
    if mysqldump -h "$host" -u "$username" -p"$password" $MYSQLDUMP_OPTIONS "$db_name" | bzip2 > "$backup_filepath"; then
        log_message "Dump compactado realizado com sucesso."
    else
        log_message "ERRO: Falha ao realizar o dump compactado."
        [ -f "$backup_filepath" ] && rm -f "$backup_filepath"  # Limpar arquivo parcial
        exit 1
    fi
fi

# Verificar se o arquivo compactado foi criado e não está vazio
if [ ! -s "$backup_filepath" ]; then
    log_message "ERRO: Arquivo de backup compactado está vazio ou não foi criado."
    exit 1
fi

# Manter apenas os 7 backups mais recentes
log_message "Limpando backups antigos (mantendo apenas os 7 mais recentes)..."

# Contar quantos backups existem para esta base de dados
backup_count=$(find "$backup_dir" -name "${db_name}_*.sql.bz2" -type f | wc -l)

if [ "$backup_count" -gt 7 ]; then
    # Usar ls para ordenar por data e remover os mais antigos
    excess_count=$((backup_count - 7))

    # Listar arquivos ordenados por data de modificação (mais antigos primeiro)
    ls -1t "$backup_dir"/${db_name}_*.sql.bz2 | tail -n "$excess_count" | \
    while read -r old_backup; do
        log_message "Removendo backup antigo: $(basename "$old_backup")"
        rm -f "$old_backup"
    done
fi

# Exibir estatísticas finais
final_backup_count=$(find "$backup_dir" -name "${db_name}_*.sql.bz2" -type f | wc -l | tr -d ' ')
backup_size=$(du -h "$backup_filepath" | cut -f1)
total_size=$(du -sh "$backup_dir" | cut -f1)

log_message "Backup concluído com sucesso!"
log_message "Localização: $backup_filepath"
log_message "Tamanho do arquivo: $backup_size"
log_message "Total de backups mantidos: $final_backup_count"
log_message "Espaço total dos backups: $total_size"
