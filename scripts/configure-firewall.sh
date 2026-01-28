#!/usr/bin/env bash
#
# configure-firewall.sh - Configure firewall for Observability Stack
#
# NOTE: Firewall configuration is automatically handled by install.sh if
#       CONFIGURE_FIREWALL=true in .env file. This standalone script is
#       provided for manual configuration or troubleshooting only.
#
# This script configures firewalld to allow required traffic for:
# - Grafana UI (port 3000)
# - InfluxDB API for LibreNMS (port 8086)
#
# Usage:
#   sudo ./scripts/configure-firewall.sh --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
ADMIN_SUBNET=""
LIBRENMS_IP=""
DRY_RUN=false

#############################################################################
# Functions
#############################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Configure firewall rules for Observability Stack

Options:
  --admin-subnet CIDR    Subnet allowed to access Grafana UI (e.g., 10.1.10.0/24)
  --librenms-ip IP       IP address of LibreNMS VM (e.g., 10.2.2.100)
  --dry-run              Show commands without executing
  -h, --help             Show this help message

Examples:
  # Allow Grafana access from entire /24 subnet
  sudo $0 --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100

  # Allow Grafana access from single IP
  sudo $0 --admin-subnet 10.1.10.50/32 --librenms-ip 10.2.2.100

  # Dry run to see commands
  sudo $0 --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100 --dry-run

EOF
  exit 0
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

check_firewalld() {
  if ! command -v firewall-cmd &> /dev/null; then
    log_error "firewalld is not installed"
    log_info "Install it with: dnf install firewalld"
    exit 1
  fi

  if ! systemctl is-active --quiet firewalld; then
    log_error "firewalld is not running"
    log_info "Start it with: systemctl start firewalld"
    exit 1
  fi

  log_success "firewalld is installed and running"
}

validate_subnet() {
  local subnet="$1"
  if [[ ! "${subnet}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_error "Invalid subnet format: ${subnet}"
    log_info "Expected format: 10.1.10.0/24"
    exit 1
  fi
}

validate_ip() {
  local ip="$1"
  if [[ ! "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Invalid IP address format: ${ip}"
    log_info "Expected format: 10.2.2.100"
    exit 1
  fi
}

run_command() {
  local cmd="$*"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would execute: ${cmd}"
  else
    log_info "Executing: ${cmd}"
    eval "${cmd}"
  fi
}

configure_grafana_access() {
  log_info "Configuring Grafana access (port 3000) for ${ADMIN_SUBNET}..."

  # Add rich rule for Grafana UI
  run_command "firewall-cmd --permanent \
    --add-rich-rule='rule family=\"ipv4\" source address=\"${ADMIN_SUBNET}\" \
    port port=\"3000\" protocol=\"tcp\" accept'"

  log_success "Grafana access configured for ${ADMIN_SUBNET}"
}

configure_influxdb_access() {
  log_info "Configuring InfluxDB access (port 8086) for LibreNMS at ${LIBRENMS_IP}..."

  # Add rich rule for InfluxDB API
  run_command "firewall-cmd --permanent \
    --add-rich-rule='rule family=\"ipv4\" source address=\"${LIBRENMS_IP}/32\" \
    port port=\"8086\" protocol=\"tcp\" accept'"

  log_success "InfluxDB access configured for ${LIBRENMS_IP}"
}

verify_rules() {
  log_info "Verifying firewall rules..."

  if [[ "${DRY_RUN}" == "false" ]]; then
    echo ""
    log_info "Current firewall rules:"
    firewall-cmd --list-rich-rules | grep -E "(3000|8086)" || true
    echo ""
  fi
}

reload_firewall() {
  if [[ "${DRY_RUN}" == "false" ]]; then
    log_info "Reloading firewall..."
    firewall-cmd --reload
    log_success "Firewall reloaded"
  else
    log_info "[DRY-RUN] Would reload firewall"
  fi
}

show_summary() {
  cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════╗
║           Firewall Configuration Summary                   ║
╚════════════════════════════════════════════════════════════╝${NC}

${GREEN}✓${NC} Grafana UI Access:
  - Port: 3000/tcp
  - Allowed from: ${ADMIN_SUBNET}
  - Purpose: Web UI for administrators

${GREEN}✓${NC} InfluxDB API Access:
  - Port: 8086/tcp
  - Allowed from: ${LIBRENMS_IP}/32
  - Purpose: LibreNMS metrics push

${YELLOW}⚠${NC}  Blocked (Internal-only):
  - Prometheus: 9090/tcp
  - Loki: 3100/tcp
  - These services are accessible only via Podman network

${BLUE}ℹ${NC}  Next Steps:
  1. Test Grafana access from admin workstation:
     ${BLUE}curl http://<grafana-vm-ip>:3000${NC}

  2. Test InfluxDB access from LibreNMS VM:
     ${BLUE}curl http://<grafana-vm-ip>:8086/health${NC}

  3. Verify firewall rules:
     ${BLUE}sudo firewall-cmd --list-rich-rules${NC}

EOF
}

#############################################################################
# Main
#############################################################################

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --admin-subnet)
        ADMIN_SUBNET="$2"
        shift 2
        ;;
      --librenms-ip)
        LIBRENMS_IP="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h | --help)
        usage
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "${ADMIN_SUBNET}" ]]; then
    log_error "Missing required argument: --admin-subnet"
    usage
  fi

  if [[ -z "${LIBRENMS_IP}" ]]; then
    log_error "Missing required argument: --librenms-ip"
    usage
  fi

  # Validate formats
  validate_subnet "${ADMIN_SUBNET}"
  validate_ip "${LIBRENMS_IP}"

  # Check prerequisites
  check_root
  check_firewalld

  echo ""
  log_info "Starting firewall configuration..."
  echo ""

  # Configure rules
  configure_grafana_access
  configure_influxdb_access

  # Apply changes
  reload_firewall

  # Verify
  verify_rules

  # Show summary
  show_summary

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    log_warn "DRY-RUN mode: No changes were made"
    log_info "Run without --dry-run to apply changes"
  fi

  log_success "Firewall configuration complete"
}

main "$@"
