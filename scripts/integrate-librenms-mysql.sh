#!/usr/bin/env bash
#
# LibreNMS MySQL Datasource Integration Script
# Automates adding LibreNMS MySQL datasource to Grafana
#
# Usage:
#   ./scripts/integrate-librenms-mysql.sh <librenms-ip> [librenms-ssh-user]
#
# Example:
#   ./scripts/integrate-librenms-mysql.sh 10.1.10.58
#   ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
#
# Prerequisites:
# - Grafana observability stack deployed and running
# - SSH access to LibreNMS server
# - .env file sourced or variables exported
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*"
}

# Print banner
print_banner() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║       LibreNMS MySQL Datasource Integration                         ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check if running as root or with sudo
  if [[ $EUID -ne 0 ]] && ! sudo -n true 2> /dev/null; then
    log_error "This script requires root privileges or passwordless sudo"
    exit 1
  fi

  # Check for required commands
  for cmd in ssh curl jq; do
    if ! command -v "${cmd}" &> /dev/null; then
      log_error "Required command '${cmd}' not found"
      exit 1
    fi
  done

  # Check if .env file exists
  if [[ ! -f "${ENV_FILE}" ]]; then
    log_error ".env file not found: ${ENV_FILE}"
    exit 1
  fi

  # Source .env file
  # shellcheck disable=SC1090
  source "${ENV_FILE}"

  # Check required variables
  local required_vars=(
    "GRAFANA_ADMIN_USER"
    "GRAFANA_ADMIN_PASSWORD"
    "GRAFANA_DOMAIN"
  )

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Required variable ${var} not set in .env"
      exit 1
    fi
  done

  log_success "Prerequisites checked"
}

# Test SSH connectivity
test_ssh() {
  local ip="$1"
  local user="$2"

  log_info "Testing SSH connection to ${user}@${ip}..."

  if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${user}@${ip}" "exit 0" 2> /dev/null; then
    log_success "SSH connection successful (key-based auth)"
    return 0
  else
    log_error "SSH connection failed"
    log_info "Ensure:"
    log_info "  1. SSH server is running on ${ip}"
    log_info "  2. User ${user} exists"
    log_info "  3. SSH key is configured: ssh-copy-id ${user}@${ip}"
    return 1
  fi
}

# Get LibreNMS database credentials
get_librenms_credentials() {
  local ip="$1"
  local user="$2"

  log_info "Retrieving LibreNMS database credentials from ${ip}..."

  # Try to get credentials from librenms container
  local db_creds
  db_creds=$(ssh "${user}@${ip}" "podman exec librenms env 2>/dev/null | grep -E '(DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD)' || docker exec librenms env 2>/dev/null | grep -E '(DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD)' || echo 'ERROR'" 2> /dev/null)

  if [[ "${db_creds}" == "ERROR" ]] || [[ -z "${db_creds}" ]]; then
    log_error "Could not retrieve database credentials from container"
    log_info "Checking Quadlet/systemd configuration..."

    # Try Quadlet config
    db_creds=$(ssh "${user}@${ip}" "cat /etc/containers/systemd/librenms-db.container 2>/dev/null | grep -E 'Environment=(MYSQL_|DB_)' || echo 'ERROR'")

    if [[ "${db_creds}" == "ERROR" ]]; then
      log_error "Could not find database credentials"
      return 1
    fi
  fi

  # Parse credentials
  DB_HOST=$(echo "${db_creds}" | grep -oP 'DB_HOST=\K[^ ]+' | head -1)
  DB_PORT=$(echo "${db_creds}" | grep -oP 'DB_PORT=\K[^ ]+' | head -1)
  DB_NAME=$(echo "${db_creds}" | grep -oP 'DB_NAME=\K[^ ]+' | head -1)
  DB_USER=$(echo "${db_creds}" | grep -oP 'DB_USER=\K[^ ]+' | head -1)
  DB_PASSWORD=$(echo "${db_creds}" | grep -oP 'DB_PASSWORD=\K[^ ]+' | head -1)

  # Defaults if not found
  DB_HOST="${DB_HOST:-librenms-db}"
  DB_PORT="${DB_PORT:-3306}"
  DB_NAME="${DB_NAME:-librenms}"
  DB_USER="${DB_USER:-librenms}"

  if [[ -z "${DB_PASSWORD}" ]]; then
    log_error "Database password not found"
    return 1
  fi

  log_success "Database credentials retrieved"
  echo ""
  echo "  Database: ${DB_NAME}"
  echo "  User: ${DB_USER}"
  echo "  Port: ${DB_PORT}"
  echo ""
}

# Expose MySQL port if needed
expose_mysql_port() {
  local ip="$1"
  local user="$2"

  log_info "Checking if MySQL port is exposed..."

  # Check if port is already exposed
  local port_check
  port_check=$(ssh "${user}@${ip}" "podman ps 2>/dev/null | grep librenms-db | grep -o '0.0.0.0:3306' || docker ps 2>/dev/null | grep librenms-db | grep -o '0.0.0.0:3306' || echo 'NOT_EXPOSED'")

  if [[ "${port_check}" == *"3306"* ]]; then
    log_success "MySQL port is already exposed"
    return 0
  fi

  log_warn "MySQL port is not exposed, attempting to add..."

  # Check if using Quadlet
  local quadlet_file="/etc/containers/systemd/librenms-db.container"
  # shellcheck disable=SC2029
  if ssh "${user}@${ip}" "test -f '${quadlet_file}'" 2> /dev/null; then
    log_info "Found Quadlet configuration, adding PublishPort..."

    # Check if PublishPort already exists but not active
    # shellcheck disable=SC2029
    if ssh "${user}@${ip}" "grep -q 'PublishPort=3306:3306' '${quadlet_file}'"; then
      log_info "PublishPort already in config, reloading service..."
    else
      # Add PublishPort after Volume line
      # shellcheck disable=SC2029
      ssh "${user}@${ip}" "sudo sed -i '/^Volume=/a PublishPort=3306:3306' '${quadlet_file}'"
      log_success "PublishPort added to Quadlet config"
    fi

    # Reload and restart
    log_info "Reloading systemd and restarting database..."
    ssh "${user}@${ip}" "sudo systemctl daemon-reload && sudo systemctl restart librenms-db.service"
    sleep 5

    # Verify
    port_check=$(ssh "${user}@${ip}" "podman ps | grep librenms-db | grep -o '0.0.0.0:3306' || echo 'FAILED'")
    if [[ "${port_check}" == *"3306"* ]]; then
      log_success "MySQL port successfully exposed"
      return 0
    else
      log_error "Failed to expose MySQL port"
      return 1
    fi
  else
    log_error "Could not find Quadlet configuration"
    log_info "Manual intervention required to expose port 3306"
    return 1
  fi
}

# Test MySQL connectivity
test_mysql_connectivity() {
  local ip="$1"

  log_info "Testing MySQL connectivity from Grafana server..."

  if timeout 3 bash -c "echo > /dev/tcp/${ip}/3306" 2> /dev/null; then
    log_success "MySQL port 3306 is reachable"
    return 0
  else
    log_error "Cannot reach MySQL port 3306 on ${ip}"
    log_info "Check firewall on LibreNMS server"
    return 1
  fi
}

# Check if datasource already exists
check_existing_datasource() {
  local datasource_name="$1"

  log_info "Checking for existing datasource '${datasource_name}'..."

  local existing_id
  existing_id=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "https://localhost:3000/api/datasources" -k |
    jq -r ".[] | select(.name==\"${datasource_name}\") | .id" 2> /dev/null)

  if [[ -n "${existing_id}" ]] && [[ "${existing_id}" != "null" ]]; then
    log_warn "Datasource '${datasource_name}' already exists (ID: ${existing_id})"
    read -r -p "Delete and recreate? [y/N] " response
    if [[ "${response}" =~ ^[Yy]$ ]]; then
      log_info "Deleting existing datasource..."
      curl -s -X DELETE -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
        "https://localhost:3000/api/datasources/${existing_id}" -k > /dev/null
      log_success "Existing datasource deleted"
      return 0
    else
      log_info "Keeping existing datasource"
      return 1
    fi
  else
    log_info "No existing datasource found"
    return 0
  fi
}

# Create Grafana datasource
create_datasource() {
  local librenms_ip="$1"
  local datasource_name="LibreNMS-MySQL"

  log_info "Creating Grafana datasource '${datasource_name}'..."

  # Create JSON payload
  local payload
  payload=$(
    cat << EOF
{
  "name": "${datasource_name}",
  "type": "mysql",
  "access": "proxy",
  "url": "${librenms_ip}:${DB_PORT}",
  "database": "${DB_NAME}",
  "user": "${DB_USER}",
  "secureJsonData": {
    "password": "${DB_PASSWORD}"
  },
  "jsonData": {
    "maxOpenConns": 5,
    "maxIdleConns": 2,
    "connMaxLifetime": 14400
  },
  "isDefault": false
}
EOF
  )

  local response
  response=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "https://localhost:3000/api/datasources" -k \
    -d "${payload}")

  # Check if successful
  local ds_id
  ds_id=$(echo "${response}" | jq -r '.datasource.id // .id // empty' 2> /dev/null)

  if [[ -n "${ds_id}" ]] && [[ "${ds_id}" != "null" ]]; then
    log_success "Datasource created successfully (ID: ${ds_id})"
    echo "${ds_id}"
    return 0
  else
    log_error "Failed to create datasource"
    echo "${response}" | jq '.' 2> /dev/null || echo "${response}"
    return 1
  fi
}

# Test datasource with sample query
test_datasource() {
  local ds_uid="$1"

  log_info "Testing datasource with sample query..."

  local query_payload
  query_payload=$(
    cat << EOF
{
  "queries": [
    {
      "refId": "A",
      "datasource": {"type": "mysql", "uid": "${ds_uid}"},
      "rawSql": "SELECT COUNT(*) as device_count FROM devices WHERE disabled=0",
      "format": "table"
    }
  ]
}
EOF
  )

  local result
  result=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "https://localhost:3000/api/ds/query" -k \
    -d "${query_payload}")

  local device_count
  device_count=$(echo "${result}" | jq -r '.results.A.frames[0].data.values[0][0] // empty' 2> /dev/null)

  if [[ -n "${device_count}" ]] && [[ "${device_count}" =~ ^[0-9]+$ ]]; then
    log_success "Datasource query successful"
    log_info "Found ${device_count} active devices in LibreNMS"
    return 0
  else
    log_error "Datasource query failed"
    return 1
  fi
}

# Main function
main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <librenms-ip> [ssh-user]"
    echo ""
    echo "Example:"
    echo "  $0 10.1.10.58"
    echo "  $0 10.1.10.58 root"
    exit 1
  fi

  local librenms_ip="$1"
  local ssh_user="${2:-root}"

  print_banner

  log_info "Target LibreNMS server: ${librenms_ip}"
  log_info "SSH user: ${ssh_user}"
  echo ""

  check_prerequisites

  if ! test_ssh "${librenms_ip}" "${ssh_user}"; then
    exit 1
  fi

  if ! get_librenms_credentials "${librenms_ip}" "${ssh_user}"; then
    exit 1
  fi

  if ! expose_mysql_port "${librenms_ip}" "${ssh_user}"; then
    log_error "Failed to expose MySQL port"
    exit 1
  fi

  if ! test_mysql_connectivity "${librenms_ip}"; then
    exit 1
  fi

  if ! check_existing_datasource "LibreNMS-MySQL"; then
    log_info "Skipping datasource creation"
    exit 0
  fi

  local ds_id
  if ! ds_id=$(create_datasource "${librenms_ip}"); then
    exit 1
  fi

  # Get datasource UID for testing
  local ds_uid
  ds_uid=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "https://localhost:3000/api/datasources/${ds_id}" -k |
    jq -r '.uid' 2> /dev/null)

  if [[ -n "${ds_uid}" ]] && [[ "${ds_uid}" != "null" ]]; then
    if test_datasource "${ds_uid}"; then
      echo ""
      log_success "LibreNMS MySQL datasource integration complete!"
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      echo "  Access in Grafana:"
      echo "  1. Navigate to: https://${GRAFANA_DOMAIN}:3000"
      echo "  2. Go to: ☰ Menu → Explore"
      echo "  3. Select datasource: LibreNMS-MySQL"
      echo "  4. Run SQL queries against LibreNMS database"
      echo ""
      echo "  Example query:"
      echo "    SELECT hostname, sysName, os, status"
      echo "    FROM devices"
      echo "    WHERE disabled=0;"
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""
    fi
  fi
}

main "$@"
