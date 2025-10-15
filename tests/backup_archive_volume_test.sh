#!/usr/bin/env bash
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${TEST_DIR}/.." && pwd)

# shellcheck disable=SC1090
source "${PROJECT_ROOT}/scripts/backup.sh"
set +e
set -o pipefail

PASS_COUNT=0
FAIL_COUNT=0

fail() {
  local message=$1
  echo "[FAIL] ${message}" >&2
  ((FAIL_COUNT++))
}

pass() {
  local message=$1
  echo "[PASS] ${message}"
  ((PASS_COUNT++))
}

assert_equals() {
  local expected=$1
  local actual=$2
  local message=$3

  if [[ "${expected}" == "${actual}" ]]; then
    pass "${message}"
  else
    fail "${message}: expected '${expected}' but got '${actual}'"
  fi
}

assert_file_exists() {
  local path=$1
  local message=$2

  if [[ -f "${path}" ]]; then
    pass "${message}"
  else
    fail "${message}: file not found at ${path}"
  fi
}

assert_file_not_exists() {
  local path=$1
  local message=$2

  if [[ ! -f "${path}" ]]; then
    pass "${message}"
  else
    fail "${message}: unexpected file at ${path}"
  fi
}

setup_docker_stub() {
  FAKE_DOCKER_VOLUMES=$(mktemp -d)
  STUB_BIN=$(mktemp -d)

  cat <<'STUB' > "${STUB_BIN}/docker"
#!/usr/bin/env bash
set -euo pipefail

command=$1
shift || true

case "${command}" in
  volume)
    action=$1
    shift || true
    if [[ "${action}" == "inspect" ]]; then
      volume_name=$1
      if [[ -d "${FAKE_DOCKER_VOLUMES}/${volume_name}" ]]; then
        exit 0
      else
        echo "Error: No such volume ${volume_name}" >&2
        exit 1
      fi
    fi
    ;;
  run)
    volume_dir=""
    backup_dir=""
    cmd=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -v)
          mapping=$2
          host_path=${mapping%%:*}
          container_path=${mapping#*:}
          container_path=${container_path%%:*}
          if [[ "${container_path}" == "/source" ]]; then
            volume_dir="${FAKE_DOCKER_VOLUMES}/${host_path}"
          elif [[ "${container_path}" == "/backup" ]]; then
            backup_dir="${host_path}"
          fi
          shift 2
          ;;
        sh)
          shift
          ;;
        -c)
          cmd=$2
          shift 2
          ;;
        --rm|alpine:3.20)
          shift
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ -z "${cmd}" ]]; then
      echo "docker stub: missing command" >&2
      exit 1
    fi

    mkdir -p "${backup_dir}"
    archive_name=$(sed -n 's/.*tar czf \/backup\/\([^ ]*\) .*/\1/p' <<<"${cmd}")
    if [[ -z "${archive_name}" ]]; then
      echo "docker stub: unable to parse archive name" >&2
      exit 1
    fi

    tar czf "${backup_dir}/${archive_name}" -C "${volume_dir}" .
    exit 0
    ;;
  *)
    echo "docker stub: unsupported command '${command}'" >&2
    exit 1
    ;;
 esac
STUB

  chmod +x "${STUB_BIN}/docker"
  export PATH="${STUB_BIN}:${PATH}"
  export FAKE_DOCKER_VOLUMES
}

cleanup() {
  rm -rf "${TMP_DIR:-}"
  rm -rf "${FAKE_DOCKER_VOLUMES:-}"
  rm -rf "${STUB_BIN:-}"
}

trap cleanup EXIT

run_tests() {
  setup_docker_stub

  TMP_DIR=$(mktemp -d)
  INCLUDED_VOLUMES=()

  # Missing volume should log a warning and not create an archive
  warn_output=$(archive_volume "nonexistent-volume" "missing.tar.gz" 2>&1)
  status=$?

  assert_equals "0" "${status}" "archive_volume returns success for missing volumes"
  if [[ "${warn_output}" == *"[WARN] Volume 'nonexistent-volume' not found. Skipping."* ]]; then
    pass "archive_volume logs warning for missing volume"
  else
    fail "archive_volume logs warning for missing volume"
  fi
  assert_equals "0" "${#INCLUDED_VOLUMES[@]}" "missing volume not added to INCLUDED_VOLUMES"
  assert_file_not_exists "${TMP_DIR}/missing.tar.gz" "missing volume archive not created"

  # Existing volume should be archived and tracked
  local volume_name="existing-volume"
  local archive_name="existing.tar.gz"
  mkdir -p "${FAKE_DOCKER_VOLUMES}/${volume_name}"
  echo "hello" > "${FAKE_DOCKER_VOLUMES}/${volume_name}/test.txt"

  archive_volume "${volume_name}" "${archive_name}"

  assert_equals "1" "${#INCLUDED_VOLUMES[@]}" "existing volume added to INCLUDED_VOLUMES"
  assert_equals "${volume_name}" "${INCLUDED_VOLUMES[0]}" "existing volume recorded by name"
  assert_file_exists "${TMP_DIR}/${archive_name}" "existing volume archive created"

  if tar tzf "${TMP_DIR}/${archive_name}" | grep -q "test.txt"; then
    pass "existing volume archive contains volume contents"
  else
    fail "existing volume archive contains volume contents"
  fi
}

run_tests

if (( FAIL_COUNT > 0 )); then
  echo "${PASS_COUNT} tests passed, ${FAIL_COUNT} failed" >&2
  exit 1
fi

echo "${PASS_COUNT} tests passed"

