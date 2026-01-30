# MySQL Tools

Scripts para backup e restore de bases de dados MySQL.

## Requisitos

- Bash
- MySQL client (`mysql`, `mysqldump`)
- `bzip2` para compressão/descompressão
- `gzip` para descompressão (restore)
- `rsync` e `ssh` (apenas para restore remoto)

## mysql_backup.sh

Realiza backup de uma base de dados MySQL, compactando com bzip2 e mantendo os 7 backups mais recentes.

### Uso

```bash
./mysql_backup.sh <arquivo_config>
```

### Configuração

Crie um arquivo `.conf` com as seguintes variáveis:

```bash
# Obrigatórias
host=localhost
username=seu_usuario
password=sua_senha        # pode ser vazio para usuários sem senha
db_name=nome_da_base
backup_dir=/caminho/para/backups

# Opcionais
port=3306                 # padrão: 3306
log_timestamp=true        # padrão: false
```

### Exemplo

```bash
# backup_config/producao.conf
host=localhost
port=3306
username=backup_user
password=senha_segura
db_name=minha_aplicacao
backup_dir=/var/backups/mysql
log_timestamp=true
```

```bash
./mysql_backup.sh backup_config/producao.conf
```

### Funcionalidades

- Compressão direta com bzip2 (sem arquivo intermediário)
- Verificação de integridade do arquivo compactado
- Rotação automática (mantém 7 backups mais recentes)
- Alerta de espaço em disco baixo
- Limpeza automática em caso de interrupção

## mysql_restore.sh

Restaura o backup mais recente de um servidor remoto para uma base de dados local.

### Uso

```bash
./mysql_restore.sh <arquivo_config>
```

### Configuração

Crie um arquivo `.conf` com as seguintes variáveis:

```bash
# Obrigatórias
ssh_host=servidor_remoto          # hostname ou alias do ~/.ssh/config
remote_backup_dir=/caminho/backups
target_db=nome_da_base_local

# Opcionais
ssh_user=usuario_ssh              # padrão: usuário atual
ssh_port=22                       # padrão: 22
local_tmp_dir=/tmp/mysql_dumps    # padrão: $TMPDIR/mysql_dumps
mysql_host=localhost              # padrão: localhost
mysql_port=3306                   # padrão: 3306
mysql_user=root                   # padrão: root
mysql_password=                   # padrão: vazio
log_timestamp=true                # padrão: false

# Scripts pós-restore (opcionais)
post_restore_inline_script='UPDATE config SET env="dev";'
post_restore_file_script=ajustes.sql   # caminho relativo ao .conf
```

### Exemplo

```bash
# restore_config/dev.conf
ssh_host=producao
remote_backup_dir=/var/backups/mysql
target_db=app_dev
mysql_user=root
mysql_password=senha_local
post_restore_file_script=sanitize.sql
```

```bash
./mysql_restore.sh restore_config/dev.conf
```

### Funcionalidades

- Busca automaticamente o backup mais recente (`.sql.bz2` ou `.sql.gz`)
- Cria a base de dados local se não existir
- Suporta scripts SQL pós-restore (inline ou arquivo)
- Limpeza automática de dumps locais com mais de 7 dias

## Segurança

- As senhas são passadas via variável de ambiente `MYSQL_PWD`, evitando exposição no `ps aux`
- Arquivos `.conf` devem ter permissões restritas: `chmod 600 *.conf`

## mysql_s3_backup.sh

Envia para o S3 o primeiro backup do mês encontrado no diretório de backups.

### Uso

```bash
./mysql_s3_backup.sh <arquivo_config>
```

### Configuração

Crie um arquivo `.conf` com as seguintes variáveis:

```bash
# Obrigatórias
db_name=nome_da_base
backup_dir=/caminho/para/backups
s3_dest=s3://bucket/pasta
aws_cli_path=/caminho/para/aws

# Opcionais
aws_cli_path=/caminho/para/aws  # padrão: /usr/local/bin
log_timestamp=true              # padrão: false
```

### Exemplo

```bash
# s3_backup.conf
db_name=producao
backup_dir=/data/backup/db/producao
s3_dest=s3://my-backup-bucket/database
log_timestamp=true
```

```bash
./mysql_s3_backup.sh s3_backup.conf
```

### Funcionalidades

- Seleciona o primeiro backup do mês atual baseado no nome do arquivo
- Garante apenas 1 backup por mês no S3 (se já existir qualquer backup do mês, não envia outro)

## Uso com cron

```bash
# Backup diário às 3h
0 3 * * * /caminho/mysql_tools/mysql_backup.sh /caminho/config/producao.conf >> /var/log/mysql_backup.log 2>&1

# Upload mensal diário (seleciona o primeiro backup do mês)
10 3 * * * /caminho/mysql_tools/mysql_s3_backup.sh /caminho/config/s3_backup.conf >> /var/log/mysql_s3_backup.log 2>&1
```

## Licença

MIT
