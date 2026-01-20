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
username=seu_usuario
password=sua_senha        # pode ser vazio para usuários sem senha
host=localhost
backup_dir=/caminho/para/backups
db_name=nome_da_base

# Opcionais
log_timestamp=true        # padrão: false
```

### Exemplo

```bash
# backup_config/producao.conf
username=backup_user
password=senha_segura
host=localhost
backup_dir=/var/backups/mysql
db_name=minha_aplicacao
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
mysql_user=root                   # padrão: root
mysql_password=                   # padrão: vazio
mysql_host=localhost              # padrão: localhost
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

## Uso com cron

```bash
# Backup diário às 3h
0 3 * * * /caminho/mysql_tools/mysql_backup.sh /caminho/config/producao.conf >> /var/log/mysql_backup.log 2>&1
```

## Licença

MIT
