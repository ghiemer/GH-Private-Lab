#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Secure one-file backup for the GH Private Lab deployment
# -----------------------------------------------------------------------------
# Collects database dumps, essential Docker volumes, and configuration files
# into a temporary workspace, compresses them, and encrypts the archive using
# OpenSSL (AES-256-CBC with PBKDF2). The resulting file is written to the
# designated backup directory.
#
# Usage:
#   BACKUP_PASSWORD="your-strong-passphrase" ./scripts/backup.sh [target_dir]
#
# Environment variables:
#   BACKUP_PASSWORD   (required) encryption passphrase; alternatively pass via
#                     file descriptor or OpenSSL-compatible method.
#   BACKUP_ROOT       (optional) default output directory for backups.
#   BACKUP_RETENTION_DAYS (optional) remove encrypted archives older than N days.
#   POSTGRES_CONTAINER (optional) container name hosting PostgreSQL (default: postgres).
#
# Dependencies:
#   - docker CLI access with permission to talk to the daemon
#   - openssl
#   - tar, gzip, mktemp (coreutils / busybox)
# -----------------------------------------------------------------------------

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set -a
  source "${PROJECT_ROOT}/.env"
  set +a
fi

if [[ -z "${BACKUP_PASSWORD:-}" ]]; then
  echo "[ERROR] BACKUP_PASSWORD must be set (passphrase for encryption)" >&2
  exit 1
fi

BACKUP_ROOT=${1:-${BACKUP_ROOT:-"${PROJECT_ROOT}/backups"}}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-postgres}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${BACKUP_ROOT}/n8n_full_backup_${TIMESTAMP}.tar.gz.enc"

mkdir -p "${BACKUP_ROOT}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM

log() {
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
}

# ----------------------------------------------------------------------------
# PostgreSQL logical dump
# ----------------------------------------------------------------------------
log "Dumping PostgreSQL database"

PGUSER=${DB_POSTGRESDB_USER:-n8n}
PGDATABASE=${DB_POSTGRESDB_DATABASE:-n8n}
PGPASSWORD_VALUE=${DB_POSTGRESDB_PASSWORD:-n8n}

PG_DUMP_PATH="${TMP_DIR}/postgres_${TIMESTAMP}.sql"

docker exec \
  -e PGPASSWORD="${PGPASSWORD_VALUE}" \
  "${POSTGRES_CONTAINER}" \
  pg_dump \
    -U "${PGUSER}" \
    -d "${PGDATABASE}" \
    --no-owner \
    --no-privileges \
    --clean \
    --if-exists \
    --create \
    --verbose \
  > "${PG_DUMP_PATH}"

log "Compressing PostgreSQL dump"
gzip -9 "${PG_DUMP_PATH}"
PG_DUMP_PATH+=".gz"

# ----------------------------------------------------------------------------
# Docker volumes
# ----------------------------------------------------------------------------
log "Archiving Docker volumes"

INCLUDED_VOLUMES=()

archive_volume() {
  local volume_name=$1
  local archive_name=$2

  if ! docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    log "[WARN] Volume '${volume_name}' not found. Skipping."
    return
  fi

  docker run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${TMP_DIR}:/backup" \
    alpine:3.20 \
    sh -c "cd /source && tar czf /backup/${archive_name} ."

  INCLUDED_VOLUMES+=("${volume_name}")
}

archive_volume "gh-private-lab_n8n-data" "n8n_data_${TIMESTAMP}.tar.gz"
archive_volume "gh-private-lab_caddy-data" "caddy_data_${TIMESTAMP}.tar.gz"
archive_volume "gh-private-lab_caddy-config" "caddy_config_${TIMESTAMP}.tar.gz"

# ----------------------------------------------------------------------------
# Configuration files & metadata
# ----------------------------------------------------------------------------
log "Collecting configuration files"

CONFIG_ARCHIVE="${TMP_DIR}/configs_${TIMESTAMP}.tar.gz"

CONFIG_ITEMS=(
  "docker-compose.yml"
  "Caddyfile"
  ".env"
  ".env.local"
  ".env.production"
  ".env.example"
  "sync_config.jsonc"
  "backup.sh"
)

EXISTING_CONFIGS=()
for item in "${CONFIG_ITEMS[@]}"; do
  if [[ -e "${PROJECT_ROOT}/${item}" ]]; then
    EXISTING_CONFIGS+=("${item}")
  fi
done

if (( ${#EXISTING_CONFIGS[@]} > 0 )); then
  tar -czf "${CONFIG_ARCHIVE}" -C "${PROJECT_ROOT}" "${EXISTING_CONFIGS[@]}"
else
  rm -f "${CONFIG_ARCHIVE}"
  CONFIG_ARCHIVE=""
fi

# Backup manifest
cat <<EOF > "${TMP_DIR}/backup_${TIMESTAMP}.info"
Backup created: ${TIMESTAMP}
Output file: $(basename "${OUTPUT_FILE}")
Host: $(hostname)
PostgreSQL user: ${PGUSER}
PostgreSQL database: ${PGDATABASE}
Included volumes: ${INCLUDED_VOLUMES[*]:-<none>}
Configuration archive: $(basename "${CONFIG_ARCHIVE:-none}")
Retention: ${BACKUP_RETENTION_DAYS} days
EOF

# ----------------------------------------------------------------------------
# Encrypt bundled archive
# ----------------------------------------------------------------------------
log "Creating encrypted backup archive"

pushd "${TMP_DIR}" >/dev/null

tar czf - . \
  | openssl enc -aes-256-cbc -pbkdf2 -salt -pass env:BACKUP_PASSWORD \
  > "${OUTPUT_FILE}"

popd >/dev/null

log "Encrypted backup written to ${OUTPUT_FILE}"

# ----------------------------------------------------------------------------
# Retention cleanup
# ----------------------------------------------------------------------------
log "Removing backups older than ${BACKUP_RETENTION_DAYS} days"
find "${BACKUP_ROOT}" -name "n8n_full_backup_*.tar.gz.enc" -mtime +"${BACKUP_RETENTION_DAYS}" -delete 2>/dev/null || true

log "Backup completed successfully"