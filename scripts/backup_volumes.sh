#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Backup Docker named volumes defined in docker-compose.yml
# -----------------------------------------------------------------------------
# Usage:
#   ./scripts/backup_volumes.sh [backup_directory]
#
# The script will create timestamped tar.gz archives for each volume and store
# them in the provided backup directory (default: ./backups).
#
# Requirements:
#   - Docker CLI accessible to the current user
#   - Sufficient disk space in the backup directory
#
# Restoring a volume:
#   docker run --rm -v <volume_name>:/restore -v $(pwd)/backups:/backup \
#     alpine:3.20 tar xzf /backup/<archive>.tar.gz -C /restore
# -----------------------------------------------------------------------------

VOLUMES=(
  "caddy-data"
  "caddy-config"
  "postgres-data"
  "n8n-data"
)

BACKUP_ROOT=${1:-"$(pwd)/backups"}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)

mkdir -p "${BACKUP_ROOT}"

log() {
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
}

check_prerequisites() {
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: Docker CLI not found in PATH."
    exit 1
  fi
}

backup_volume() {
  local volume_name=$1
  local archive_path=$2

  log "Backing up volume '${volume_name}' → ${archive_path}"

  docker run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${BACKUP_ROOT}:/backup" \
    alpine:3.20 \
    sh -c "cd /source && tar czf /backup/${archive_path} ."
}

write_manifest() {
  local manifest_file=$1

  cat <<EOF >"${manifest_file}"
Backup created: ${TIMESTAMP}
Host: ${HOSTNAME}
Backup directory: ${BACKUP_ROOT}

Volumes:
$(printf '  - %s\n' "${VOLUMES[@]}")

Restore example:
  docker run --rm \\
    -v <volume_name>:/restore \\
    -v \\"$(pwd)/backups\\":/backup \\
    alpine:3.20 \\
    tar xzf /backup/<archive>.tar.gz -C /restore
EOF
}

main() {
  check_prerequisites

  for volume in "${VOLUMES[@]}"; do
    archive_name="${volume}_${TIMESTAMP}.tar.gz"
    backup_volume "${volume}" "${archive_name}"
  done

  write_manifest "${BACKUP_ROOT}/backup_${TIMESTAMP}.info"

  log "Backup complete. Archives stored in ${BACKUP_ROOT}"
}

main "$@"
