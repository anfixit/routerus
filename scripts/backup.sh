#!/bin/bash
set -e

# Параметры
BACKUP_DIR="/opt/wg-manager/backups"
LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
DB_BACKUP_FILE="$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
RETENTION_DAYS=7

# Создание директории для резервных копий
mkdir -p $BACKUP_DIR

# Логирование
exec >> $LOG_FILE 2>&1
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting backup..."

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
PGUSER="wg_user"
PGHOST="127.0.0.1"
PGDATABASE="wg_manager_db"
pg_dump > $DB_BACKUP_FILE

# Проверка успешности
if [[ -f $DB_BACKUP_FILE ]]; then
    echo "Backup completed successfully: $DB_BACKUP_FILE"
else
    echo "Backup failed!"
    exit 1
fi

# Очистка старых резервных копий
echo "Removing backups older than $RETENTION_DAYS days..."
find $BACKUP_DIR -type f -name "*.sql" -mtime +$RETENTION_DAYS -exec rm -f {} \;
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Backup process completed."
