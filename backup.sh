#!/bin/bash

# =============================================================================
# n8n Backup Script
# =============================================================================
# Erstellt automatische Backups der PostgreSQL Datenbank und n8n Daten
# 
# Usage: ./backup.sh
# 
# Konfiguration über Umgebungsvariablen oder .env Datei

set -euo pipefail

# Konfiguration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# .env laden falls vorhanden
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
fi

# Backup Verzeichnis erstellen
mkdir -p "${BACKUP_DIR}"

echo "🚀 Starting n8n backup process..."
echo "📁 Backup directory: ${BACKUP_DIR}"
echo "🕐 Timestamp: ${TIMESTAMP}"

# =============================================================================
# PostgreSQL Backup
# =============================================================================
echo "📊 Creating PostgreSQL backup..."

POSTGRES_BACKUP_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql"

docker exec postgres pg_dump \
    -h localhost \
    -U "${DB_POSTGRESDB_USER:-n8n}" \
    -d "${DB_POSTGRESDB_DATABASE:-n8n}" \
    --no-password \
    --verbose \
    --clean \
    --if-exists \
    --create \
    > "${POSTGRES_BACKUP_FILE}"

# Komprimierung
echo "🗜️  Compressing PostgreSQL backup..."
gzip "${POSTGRES_BACKUP_FILE}"
POSTGRES_BACKUP_FILE="${POSTGRES_BACKUP_FILE}.gz"

echo "✅ PostgreSQL backup created: $(basename ${POSTGRES_BACKUP_FILE})"

# =============================================================================
# n8n Daten Backup
# =============================================================================
echo "📦 Creating n8n data backup..."

N8N_BACKUP_FILE="${BACKUP_DIR}/n8n_data_${TIMESTAMP}.tar.gz"

docker run --rm \
    -v n8n-data:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:latest \
    tar czf "/backup/$(basename ${N8N_BACKUP_FILE})" -C /data .

echo "✅ n8n data backup created: $(basename ${N8N_BACKUP_FILE})"

# =============================================================================
# Backup Informationen
# =============================================================================
BACKUP_INFO_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.info"

cat > "${BACKUP_INFO_FILE}" << EOF
# n8n Backup Information
# Created: $(date)
# 
# Files in this backup:
# - $(basename ${POSTGRES_BACKUP_FILE}) (PostgreSQL database dump)
# - $(basename ${N8N_BACKUP_FILE}) (n8n data volume)
#
# Restore commands:
# 
# 1. PostgreSQL:
#    gunzip -c $(basename ${POSTGRES_BACKUP_FILE}) | docker exec -i postgres psql -U ${DB_POSTGRESDB_USER:-n8n} -d ${DB_POSTGRESDB_DATABASE:-n8n}
#
# 2. n8n Data:
#    docker run --rm -v n8n-data:/data -v \$(pwd):/backup alpine:latest tar xzf /backup/$(basename ${N8N_BACKUP_FILE}) -C /data
#
# Environment at backup time:
DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER:-n8n}
DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE:-n8n}
N8N_HOST=${N8N_HOST:-not_set}
GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Vienna}
EOF

echo "📋 Backup info created: $(basename ${BACKUP_INFO_FILE})"

# =============================================================================
# Alte Backups bereinigen
# =============================================================================
echo "🧹 Cleaning up old backups (older than ${BACKUP_RETENTION_DAYS} days)..."

find "${BACKUP_DIR}" -name "postgres_*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "n8n_data_*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "backup_*.info" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true

# =============================================================================
# Backup Statistiken
# =============================================================================
POSTGRES_SIZE=$(du -h "${POSTGRES_BACKUP_FILE}" | cut -f1)
N8N_SIZE=$(du -h "${N8N_BACKUP_FILE}" | cut -f1)
TOTAL_BACKUPS=$(ls -1 "${BACKUP_DIR}"/postgres_*.sql.gz 2>/dev/null | wc -l)

echo ""
echo "🎉 Backup completed successfully!"
echo "📊 Statistics:"
echo "   PostgreSQL backup: ${POSTGRES_SIZE}"
echo "   n8n data backup: ${N8N_SIZE}"
echo "   Total backups retained: ${TOTAL_BACKUPS}"
echo ""
echo "💡 To restore, see instructions in: $(basename ${BACKUP_INFO_FILE})"