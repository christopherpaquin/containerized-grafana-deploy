#!/usr/bin/env bash
#
# Observability Stack Uninstallation Script
# Removes all components deployed by install.sh
#
# This script cleanly removes:
# - All containers
# - Quadlet files
# - Podman network
# - Data directories (with confirmation)
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly OBS_BASE_DIR="/srv/obs"
readonly QUADLET_DIR="/etc/containers/systemd"

# Services to remove (in reverse dependency order)
readonly SERVICES=(
  "grafana"
  "alloy"
  "loki"
  "prometheus"
  "influxdb"
  "obs-network-network" # Generated from obs-network.network
)

# Global flags
DRY_RUN=false
REMOVE_DATA="no"

# Logging functions
log_info() {
  local prefix="${BLUE}[INFO]${NC}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    prefix="${BLUE}[DRY-RUN]${NC}"
  fi
  echo -e "${prefix} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Execute command (skip if dry-run)
execute_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${BLUE}[WOULD RUN]${NC} $*"
    return 0
  else
    "$@"
  fi
}

# Check if running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

# Confirm uninstallation
confirm_uninstall() {
  local remove_data="${1:-no}"

  echo ""

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY-RUN MODE: No changes will be made"
    echo ""
    echo "The following actions would be performed:"
  else
    log_warn "This will remove all Observability Stack components"
  fi

  echo ""
  echo "  The following services will be stopped and removed:"
  for service in "${SERVICES[@]}"; do
    echo "    - ${service}"
  done
  echo ""

  if [[ "${remove_data}" == "yes" ]]; then
    log_warn "DATA WILL BE PERMANENTLY DELETED: ${OBS_BASE_DIR}"
    echo ""
  else
    log_info "Data will be preserved in: ${OBS_BASE_DIR}"
    log_info "To remove data, run: $0 --remove-data"
    echo ""
  fi

  # Skip confirmation in dry-run mode
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  read -r -p "Are you sure you want to continue? [y/N] " response
  if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    log_info "Uninstallation cancelled"
    exit 0
  fi
}

# Stop and disable services
stop_services() {
  log_info "Stopping and disabling services..."

  for service in "${SERVICES[@]}"; do
    local service_name="${service}.service"

    if systemctl is-active --quiet "${service_name}" 2> /dev/null; then
      log_info "Stopping ${service}..."
      execute_cmd systemctl stop "${service_name}" || log_warn "Failed to stop ${service}"
    fi

    if systemctl is-enabled --quiet "${service_name}" 2> /dev/null; then
      log_info "Disabling ${service}..."
      execute_cmd systemctl disable "${service_name}" 2> /dev/null || log_warn "Failed to disable ${service}"
    fi
  done

  log_success "Services stopped and disabled"
}

# Remove containers
remove_containers() {
  log_info "Removing containers..."

  local containers=(
    "grafana"
    "alloy"
    "loki"
    "prometheus"
    "influxdb"
  )

  for container in "${containers[@]}"; do
    if podman container exists "${container}" 2> /dev/null; then
      log_info "Removing container ${container}..."
      execute_cmd podman rm -f "${container}" 2> /dev/null || log_warn "Failed to remove ${container}"
    fi
  done

  log_success "Containers removed"
}

# Remove Podman network
remove_network() {
  log_info "Removing Podman network..."

  if podman network exists obs-net 2> /dev/null; then
    log_info "Removing network obs-net..."
    execute_cmd podman network rm obs-net 2> /dev/null || log_warn "Failed to remove network obs-net"
  fi

  log_success "Network removed"
}

# Remove Quadlet files
remove_quadlets() {
  log_info "Removing Quadlet files..."

  local quadlet_files=(
    "${QUADLET_DIR}/grafana.container"
    "${QUADLET_DIR}/alloy.container"
    "${QUADLET_DIR}/loki.container"
    "${QUADLET_DIR}/prometheus.container"
    "${QUADLET_DIR}/influxdb.container"
    "${QUADLET_DIR}/obs-network.network"
  )

  for file in "${quadlet_files[@]}"; do
    if [[ -f "${file}" ]]; then
      execute_cmd rm -f "${file}"
      log_info "Removed $(basename "${file}")"
    fi
  done

  log_success "Quadlet files removed"
}

# Reload systemd
reload_systemd() {
  log_info "Reloading systemd daemon..."
  execute_cmd systemctl daemon-reload
  log_success "Systemd daemon reloaded"
}

# Remove data directories
remove_data() {
  log_info "Removing data directories..."

  if [[ ! -d "${OBS_BASE_DIR}" ]]; then
    log_info "Data directory ${OBS_BASE_DIR} does not exist"
    return 0
  fi

  log_warn "Removing ${OBS_BASE_DIR}..."
  echo ""
  echo "This will permanently delete all data including:"
  echo "  - Grafana dashboards and settings"
  echo "  - InfluxDB time-series data"
  echo "  - Prometheus metrics"
  echo "  - Loki logs"
  echo "  - Alloy configuration state"
  echo ""

  # Skip confirmation in dry-run mode
  if [[ "${DRY_RUN}" != "true" ]]; then
    read -r -p "Type 'DELETE' to confirm data deletion: " confirmation
    if [[ "${confirmation}" != "DELETE" ]]; then
      log_info "Data deletion cancelled, preserving ${OBS_BASE_DIR}"
      return 0
    fi
  fi

  execute_cmd rm -rf "${OBS_BASE_DIR}"
  log_success "Data directories removed"
}

# Remove SELinux contexts
remove_selinux() {
  log_info "Removing SELinux file contexts..."

  if ! command -v semanage &> /dev/null; then
    log_warn "semanage not found, skipping SELinux cleanup"
    return 0
  fi

  if semanage fcontext -l | grep -q "${OBS_BASE_DIR}"; then
    execute_cmd semanage fcontext -d "${OBS_BASE_DIR}(/.*)?" 2> /dev/null ||
      log_warn "Failed to remove SELinux context"
    log_info "SELinux context removed"
  else
    log_info "No SELinux context found for ${OBS_BASE_DIR}"
  fi

  log_success "SELinux cleanup completed"
}

# Remove firewall rules
remove_firewall() {
  log_info "Removing firewall rules..."

  # Check if firewalld is available and running
  if ! command -v firewall-cmd &> /dev/null; then
    log_info "firewalld not found - skipping firewall cleanup"
    return 0
  fi

  if ! systemctl is-active --quiet firewalld; then
    log_info "firewalld is not running - skipping firewall cleanup"
    return 0
  fi

  local rules_removed=0

  # Get all rich rules and filter for observability stack ports
  mapfile -t rules < <(firewall-cmd --list-rich-rules)

  for rule in "${rules[@]}"; do
    # Check if rule is for Grafana (port 3000) or InfluxDB (port 8086)
    if [[ "${rule}" =~ port=\"(3000|8086)\" ]]; then
      log_info "Removing firewall rule: ${rule}"
      execute_cmd firewall-cmd --permanent --remove-rich-rule="${rule}" 2> /dev/null || true
      ((rules_removed++))
    fi
  done

  if [[ ${rules_removed} -gt 0 ]]; then
    log_info "Reloading firewall..."
    execute_cmd firewall-cmd --reload
    log_success "Removed ${rules_removed} firewall rule(s)"
  else
    log_info "No observability stack firewall rules found"
  fi

  echo ""
}

# Display final status
show_status() {
  echo ""
  log_success "Uninstallation completed!"
  echo ""

  log_info "Checking for remaining artifacts..."

  # Check for running containers
  local running_containers=0
  for container in "grafana" "alloy" "loki" "prometheus" "influxdb"; do
    if podman container exists "${container}" 2> /dev/null; then
      log_warn "Container still exists: ${container}"
      running_containers=$((running_containers + 1))
    fi
  done

  # Check for network
  if podman network exists obs-net 2> /dev/null; then
    log_warn "Network still exists: obs-net"
  fi

  # Check for data directory
  if [[ -d "${OBS_BASE_DIR}" ]]; then
    log_info "Data preserved in: ${OBS_BASE_DIR}"
    log_info "To remove data manually: rm -rf ${OBS_BASE_DIR}"
  fi

  if [[ ${running_containers} -eq 0 ]]; then
    log_success "All components removed cleanly"
  else
    log_warn "Some components may require manual cleanup"
  fi

  echo ""
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remove-data | -r)
        REMOVE_DATA="yes"
        shift
        ;;
      --preserve-data | -p)
        # This is the default behavior, but included for clarity
        REMOVE_DATA="no"
        shift
        ;;
      --dry-run | -d)
        DRY_RUN=true
        shift
        ;;
      --help | -h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run, -d        Show what would be done without actually doing it"
        echo "  --preserve-data, -p  Preserve data directories (default behavior)"
        echo "  --remove-data, -r    Remove data directories (permanent deletion)"
        echo "  --help, -h           Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 --dry-run                    # Preview what will be removed"
        echo "  $0                               # Uninstall but keep data"
        echo "  $0 --preserve-data               # Same as above (explicit)"
        echo "  $0 --remove-data                 # Uninstall and delete all data"
        echo "  $0 --dry-run --remove-data       # Preview full uninstall with data removal"
        echo ""
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 2
        ;;
    esac
  done
}

# Main uninstallation function
main() {
  # Parse arguments first to set global flags like DRY_RUN and REMOVE_DATA
  parse_args "$@"

  log_info "Starting Observability Stack uninstallation..."

  check_root
  confirm_uninstall "${REMOVE_DATA}"

  echo ""
  stop_services
  remove_containers
  remove_network
  remove_quadlets
  reload_systemd
  remove_firewall

  if [[ "${REMOVE_DATA}" == "yes" ]]; then
    remove_data
    remove_selinux
  fi

  show_status
}

# Run main function
main "$@"
