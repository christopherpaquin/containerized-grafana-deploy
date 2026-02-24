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
# - Prometheus UI and API (port 9090) - optional
#
# Usage:
#   sudo ./scripts/configure-firewall.sh --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100
#   sudo ./scripts/configure-firewall.sh --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100 --prometheus-subnet 10.1.10.0/24
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
PROMETHEUS_SUBNET=""
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
  --admin-subnet CIDR       Subnet allowed to access Grafana UI (e.g., 10.1.10.0/24)
  --librenms-ip IP          IP address of LibreNMS VM (e.g., 10.2.2.100)
  --prometheus-subnet CIDR  Subnet allowed to access Prometheus (optional, e.g., 10.1.10.0/24)
  --dry-run                 Show commands without executing
  -h, --help                Show this help message

Examples:
  # Allow Grafana access from entire /24 subnet
  sudo $0 --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100

  # Allow Grafana and Prometheus access from same subnet
  sudo $0 --admin-subnet 10.1.10.0/24 --librenms-ip 10.2.2.100 --prometheus-subnet 10.1.10.0/24

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

validate_octet() {
  local octet="$1"
  if [[ "${octet}" -lt 0 || "${octet}" -gt 255 ]]; then
    return 1
  fi
  return 0
}

validate_subnet() {
  local subnet="$1"
  if [[ ! "${subnet}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_error "Invalid subnet format: ${subnet}"
    log_info "Expected format: 10.1.10.0/24"
    exit 1
  fi

  # Extract IP and CIDR
  local ip_part="${subnet%/*}"
  local cidr_part="${subnet#*/}"

  # Validate CIDR range (0-32)
  if [[ "${cidr_part}" -lt 0 || "${cidr_part}" -gt 32 ]]; then
    log_error "Invalid CIDR range: /${cidr_part} (must be 0-32)"
    exit 1
  fi

  # Validate each octet
  IFS='.' read -r -a octets <<< "${ip_part}"
  for octet in "${octets[@]}"; do
    if ! validate_octet "${octet}"; then
      log_error "Invalid IP octet in subnet: ${octet} (must be 0-255)"
      exit 1
    fi
  done
}

validate_ip() {
  local ip="$1"
  if [[ ! "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Invalid IP address format: ${ip}"
    log_info "Expected format: 10.2.2.100"
    exit 1
  fi

  # Validate each octet
  IFS='.' read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    if ! validate_octet "${octet}"; then
      log_error "Invalid IP octet: ${octet} (must be 0-255)"
      exit 1
    fi
  done
}

run_command() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would execute: $*"
  else
    log_info "Executing: $*"
    "$@"
  fi
}

configure_grafana_access() {
  log_info "Configuring Grafana access (port 3000) for ${ADMIN_SUBNET}..."

  # Add rich rule for Grafana UI
  run_command firewall-cmd --permanent \
    --add-rich-rule="rule family=\"ipv4\" source address=\"${ADMIN_SUBNET}\" port port=\"3000\" protocol=\"tcp\" accept"

  log_success "Grafana access configured for ${ADMIN_SUBNET}"
}

configure_influxdb_access() {
  log_info "Configuring InfluxDB access (port 8086) for LibreNMS at ${LIBRENMS_IP}..."

  # Add rich rule for InfluxDB API
  run_command firewall-cmd --permanent \
    --add-rich-rule="rule family=\"ipv4\" source address=\"${LIBRENMS_IP}/32\" port port=\"8086\" protocol=\"tcp\" accept"

  log_success "InfluxDB access configured for ${LIBRENMS_IP}"
}

configure_prometheus_access() {
  if [[ -z "${PROMETHEUS_SUBNET}" ]]; then
    log_info "Prometheus subnet not configured - skipping Prometheus firewall rule"
    log_info "Prometheus will only be accessible within container network"
    return 0
  fi

  log_info "Configuring Prometheus access (port 9090) for ${PROMETHEUS_SUBNET}..."

  # Add rich rule for Prometheus UI/API
  run_command firewall-cmd --permanent \
    --add-rich-rule="rule family=\"ipv4\" source address=\"${PROMETHEUS_SUBNET}\" port port=\"9090\" protocol=\"tcp\" accept"

  log_success "Prometheus access configured for ${PROMETHEUS_SUBNET}"
}

verify_rules() {
  log_info "Verifying firewall rules..."

  if [[ "${DRY_RUN}" == "false" ]]; then
    echo ""
    log_info "Current firewall rules:"
    firewall-cmd --list-rich-rules | grep -E "(3000|8086|9090)" || true
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

EOF

  if [[ -n "${PROMETHEUS_SUBNET}" ]]; then
    cat << EOF
${GREEN}✓${NC} Prometheus UI/API Access:
  - Port: 9090/tcp
  - Allowed from: ${PROMETHEUS_SUBNET}
  - Purpose: Metrics queries and monitoring

EOF
  else
    cat << EOF
${YELLOW}⚠${NC}  Prometheus (Internal-only):
  - Port: 9090/tcp - Not exposed externally
  - Accessible only via Podman network

EOF
  fi

  cat << EOF
${YELLOW}⚠${NC}  Blocked (Internal-only):
  - Loki: 3100/tcp
  - Accessible only via Podman network

${BLUE}ℹ${NC}  Next Steps:
  1. Test Grafana access from admin workstation:
     ${BLUE}curl http://<grafana-vm-ip>:3000${NC}

  2. Test InfluxDB access from LibreNMS VM:
     ${BLUE}curl http://<grafana-vm-ip>:8086/health${NC}

EOF

  if [[ -n "${PROMETHEUS_SUBNET}" ]]; then
    cat << EOF
  3. Test Prometheus access:
     ${BLUE}curl http://<grafana-vm-ip>:9090/-/healthy${NC}

  4. Verify firewall rules:
     ${BLUE}sudo firewall-cmd --list-rich-rules${NC}

EOF
  else
    cat << EOF
  3. Verify firewall rules:
     ${BLUE}sudo firewall-cmd --list-rich-rules${NC}

EOF
  fi
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
      --prometheus-subnet)
        PROMETHEUS_SUBNET="$2"
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

  # Validate Prometheus subnet if provided
  if [[ -n "${PROMETHEUS_SUBNET}" ]]; then
    validate_subnet "${PROMETHEUS_SUBNET}"
  fi

  # Check prerequisites
  check_root
  check_firewalld

  echo ""
  log_info "Starting firewall configuration..."
  echo ""

  # Configure rules
  configure_grafana_access
  configure_influxdb_access
  configure_prometheus_access

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
