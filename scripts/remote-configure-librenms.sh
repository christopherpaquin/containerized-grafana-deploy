#!/usr/bin/env bash
#
# Remote LibreNMS Configuration Script
# Runs the LibreNMS InfluxDB configuration script on a remote server via SSH
#
# Usage:
#   ./scripts/remote-configure-librenms.sh <librenms-ip> [ssh-user]
#
# Example:
#   ./scripts/remote-configure-librenms.sh 10.1.10.58
#   ./scripts/remote-configure-librenms.sh 10.1.10.58 root
#

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

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

# Usage information
usage() {
  cat << EOF
Usage: $0 <librenms-ip> [ssh-user]

Run LibreNMS InfluxDB configuration script on remote server via SSH.

Arguments:
  librenms-ip   IP address of LibreNMS server (required)
  ssh-user      SSH username (default: root)

Examples:
  $0 10.1.10.58
  $0 10.1.10.58 root
  $0 librenms.example.com admin

Prerequisites:
  - SSH access to LibreNMS server
  - SSH key authentication configured (or will prompt for password)
  - LibreNMS running in containers (Docker or Podman)

EOF
  exit 1
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check if .env file exists
  if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    log_error ".env file not found in ${PROJECT_ROOT}"
    exit 1
  fi

  # Check if helper script exists
  if [[ ! -f "${PROJECT_ROOT}/helper/configure-librenms-influxdb.sh" ]]; then
    log_error "Configuration script not found: ${PROJECT_ROOT}/helper/configure-librenms-influxdb.sh"
    exit 1
  fi

  # Check if ssh is available
  if ! command -v ssh &> /dev/null; then
    log_error "ssh command not found. Install openssh-clients."
    exit 1
  fi

  # Check if scp is available
  if ! command -v scp &> /dev/null; then
    log_error "scp command not found. Install openssh-clients."
    exit 1
  fi

  log_success "Prerequisites checked"
}

# Test SSH connectivity
test_ssh() {
  local remote_host=$1
  local ssh_user=$2

  log_info "Testing SSH connection to ${ssh_user}@${remote_host}..."

  if ssh -o ConnectTimeout=10 -o BatchMode=yes "${ssh_user}@${remote_host}" "exit" &> /dev/null; then
    log_success "SSH connection successful (key-based auth)"
    return 0
  elif ssh -o ConnectTimeout=10 "${ssh_user}@${remote_host}" "exit" &> /dev/null; then
    log_success "SSH connection successful (password auth)"
    return 0
  else
    log_error "Cannot connect to ${ssh_user}@${remote_host}"
    log_info "Ensure:"
    log_info "  1. SSH server is running on ${remote_host}"
    log_info "  2. User ${ssh_user} exists and has sudo/root privileges"
    log_info "  3. SSH key is configured or password is correct"
    log_info ""
    log_info "To setup SSH key:"
    log_info "  ssh-copy-id ${ssh_user}@${remote_host}"
    return 1
  fi
}

# Display configuration summary
show_summary() {
  local remote_host=$1
  local ssh_user=$2

  # Source .env to get connection details
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║       Remote LibreNMS Configuration                                  ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Target Server:"
  echo "  LibreNMS Host:      ${remote_host}"
  echo "  SSH User:           ${ssh_user}"
  echo ""
  echo "InfluxDB Connection (from .env):"
  echo "  InfluxDB Server:    $(hostname -I | awk '{print $1}')"
  echo "  Port:               8086"
  echo "  Organization:       ${INFLUXDB_ORG}"
  echo "  Bucket:             ${INFLUXDB_BUCKET}"
  echo "  Token:              ${INFLUXDB_TOKEN:0:20}..."
  echo ""
}

# Main execution
main() {
  # Parse arguments
  if [[ $# -lt 1 ]]; then
    usage
  fi

  local remote_host=$1
  local ssh_user=${2:-root}

  # Run checks
  check_prerequisites
  show_summary "${remote_host}" "${ssh_user}"

  # Confirm before proceeding
  read -r -p "Proceed with configuration? [y/N] " response
  if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    log_info "Configuration cancelled"
    exit 0
  fi

  echo ""

  # Test SSH connectivity
  if ! test_ssh "${remote_host}" "${ssh_user}"; then
    exit 1
  fi

  # Copy script to remote server
  log_info "Copying configuration script to ${remote_host}..."
  if scp -q "${PROJECT_ROOT}/helper/configure-librenms-influxdb.sh" "${ssh_user}@${remote_host}:/tmp/"; then
    log_success "Script uploaded to /tmp/configure-librenms-influxdb.sh"
  else
    log_error "Failed to copy script to remote server"
    exit 1
  fi

  # Make script executable
  log_info "Setting script permissions..."
  ssh "${ssh_user}@${remote_host}" "chmod +x /tmp/configure-librenms-influxdb.sh"

  # Execute script on remote server
  echo ""
  log_info "Executing configuration script on ${remote_host}..."
  log_info "This will:"
  log_info "  1. Detect LibreNMS container and bind mounts"
  log_info "  2. Backup existing configuration"
  log_info "  3. Add InfluxDB v2 configuration"
  log_info "  4. Restart LibreNMS container"
  log_info "  5. Validate and trigger test poll"
  echo ""

  # Run script remotely (interactive mode for prompts)
  if ssh -t "${ssh_user}@${remote_host}" "sudo /tmp/configure-librenms-influxdb.sh"; then
    echo ""
    log_success "Remote configuration completed successfully!"
    echo ""
    log_info "Cleanup: Removing script from remote server..."
    ssh "${ssh_user}@${remote_host}" "rm -f /tmp/configure-librenms-influxdb.sh"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                    ✓ Configuration Complete                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    log_success "LibreNMS on ${remote_host} is now pushing metrics to InfluxDB"
    echo ""
    log_info "Next steps:"
    echo "  1. Wait 5-10 minutes for first poll cycle"
    echo "  2. Verify data in Grafana:"
    echo ""
    echo "     cd ${PROJECT_ROOT}"
    echo "     source .env"
    echo "     curl -s \"http://localhost:8086/api/v2/query?org=\${INFLUXDB_ORG}\" \\"
    echo "       -H \"Authorization: Token \${INFLUXDB_TOKEN}\" \\"
    echo "       -H \"Content-Type: application/vnd.flux\" \\"
    echo "       -d 'from(bucket:\"librenms\") |> range(start: -10m) |> limit(n: 10)'"
    echo ""
    echo "  3. Or check in Grafana UI:"
    echo "     https://$(hostname -I | awk '{print $1}'):3000"
    echo "     Go to: Explore → InfluxDB-LibreNMS datasource"
    echo ""
  else
    echo ""
    log_error "Remote configuration failed"
    log_info "Check the output above for errors"
    log_info "Script remains at: ${ssh_user}@${remote_host}:/tmp/configure-librenms-influxdb.sh"
    exit 1
  fi
}

# Run main function
main "$@"
