#!/usr/bin/env bash
#
# Observability Stack Installation Script
# Deploys Grafana, InfluxDB, Prometheus, Loki, and Alloy on RHEL 10
# using Podman Quadlets (systemd-managed containers)
#
# This script is idempotent and safe to re-run.
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

# Configuration
readonly OBS_BASE_DIR="/srv/obs"
readonly QUADLET_DIR="/etc/containers/systemd"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"

# Component directories
readonly COMPONENTS=("grafana" "influxdb" "prometheus" "loki" "alloy")

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
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

# Cleanup function for trap
cleanup() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_error "Installation failed with exit code ${exit_code}"
    log_info "Check logs with: journalctl -xe"
  fi
}

trap cleanup EXIT

# Check if running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  local missing_deps=()

  # Check for required commands
  local required_commands=("podman" "systemctl" "semanage" "restorecon")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "${cmd}" &> /dev/null; then
      missing_deps+=("${cmd}")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_info "Install with: dnf install -y podman systemd policycoreutils-python-utils"
    exit 3
  fi

  # Check Podman version
  local podman_version
  podman_version=$(podman --version | awk '{print $3}')
  log_info "Podman version: ${podman_version}"

  # Check SELinux status
  if command -v getenforce &> /dev/null; then
    local selinux_status
    selinux_status=$(getenforce)
    log_info "SELinux status: ${selinux_status}"

    if [[ "${selinux_status}" != "Enforcing" ]]; then
      log_warn "SELinux is not in enforcing mode"
    fi
  fi

  log_success "All prerequisites satisfied"
}

# Load environment variables
load_environment() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    log_error "Environment file not found: ${ENV_FILE}"
    log_info "Please copy ${ENV_EXAMPLE} to ${ENV_FILE} and configure it"
    exit 2
  fi

  log_info "Loading environment from ${ENV_FILE}"
  # shellcheck disable=SC1090
  source "${ENV_FILE}"

  # Validate required variables
  local required_vars=(
    "INFLUXDB_ADMIN_USER"
    "INFLUXDB_ADMIN_PASSWORD"
    "INFLUXDB_ORG"
    "INFLUXDB_BUCKET"
    "INFLUXDB_TOKEN"
    "GRAFANA_ADMIN_USER"
    "GRAFANA_ADMIN_PASSWORD"
    "GRAFANA_DOMAIN"
  )

  local missing_vars=()
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("${var}")
    fi
  done

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Missing required environment variables: ${missing_vars[*]}"
    exit 2
  fi

  # Validate plugin configurations
  if [[ "${GRAFANA_INSTALL_ZABBIX_PLUGIN:-false}" == "true" ]]; then
    if [[ -z "${ZABBIX_URL:-}" ]]; then
      log_warn "ZABBIX_URL is not set but Zabbix plugin is enabled"
      log_info "Zabbix datasource will need manual configuration in Grafana UI"
    fi
    if [[ -z "${ZABBIX_API_TOKEN:-}" ]]; then
      log_warn "ZABBIX_API_TOKEN is not set but Zabbix plugin is enabled"
      log_info "Zabbix datasource will need manual configuration in Grafana UI"
    fi
  fi

  # LibreNMS uses InfluxDB datasource (push-to-TSDB model), no plugin needed
  log_info "LibreNMS metrics will be queried via InfluxDB datasource (push-to-TSDB architecture)"

  log_success "Environment variables loaded"
}

# Create directory structure
create_directories() {
  log_info "Creating directory structure..."

  # Create base directory
  if [[ ! -d "${OBS_BASE_DIR}" ]]; then
    mkdir -p "${OBS_BASE_DIR}"
    log_success "Created ${OBS_BASE_DIR}"
  else
    log_info "Directory ${OBS_BASE_DIR} already exists"
  fi

  # Create component directories
  for component in "${COMPONENTS[@]}"; do
    local data_dir="${OBS_BASE_DIR}/${component}/data"
    local config_dir="${OBS_BASE_DIR}/${component}/config"

    if [[ "${component}" == "grafana" ]]; then
      # Grafana uses provisioning instead of config
      config_dir="${OBS_BASE_DIR}/${component}/provisioning"
    fi

    mkdir -p "${data_dir}"
    mkdir -p "${config_dir}"

    log_info "Created directories for ${component}"
  done

  log_success "Directory structure created"
}

# Copy configuration files
copy_configurations() {
  log_info "Copying configuration files..."

  # Prometheus config
  if [[ -f "${PROJECT_ROOT}/configs/prometheus/prometheus.yml" ]]; then
    cp -f "${PROJECT_ROOT}/configs/prometheus/prometheus.yml" \
      "${OBS_BASE_DIR}/prometheus/config/"
    log_info "Copied Prometheus configuration"
  fi

  # Loki config
  if [[ -f "${PROJECT_ROOT}/configs/loki/loki.yaml" ]]; then
    cp -f "${PROJECT_ROOT}/configs/loki/loki.yaml" \
      "${OBS_BASE_DIR}/loki/config/"
    log_info "Copied Loki configuration"
  fi

  # Alloy config
  if [[ -f "${PROJECT_ROOT}/configs/alloy/config.alloy" ]]; then
    cp -f "${PROJECT_ROOT}/configs/alloy/config.alloy" \
      "${OBS_BASE_DIR}/alloy/config/"
    log_info "Copied Alloy configuration"
  fi

  # Grafana provisioning
  if [[ -d "${PROJECT_ROOT}/configs/grafana/provisioning" ]]; then
    cp -rf "${PROJECT_ROOT}/configs/grafana/provisioning"/* \
      "${OBS_BASE_DIR}/grafana/provisioning/"
    log_info "Copied Grafana provisioning files"
  fi

  log_success "Configuration files copied"
}

# Generate TLS certificates for Grafana HTTPS
generate_tls_certificates() {
  # Check if TLS is enabled
  if [[ "${TLS_ENABLED:-false}" != "true" ]]; then
    log_info "TLS is disabled - skipping certificate generation"
    log_info "Grafana will run with HTTP only"
    return 0
  fi

  log_info "TLS is enabled - generating self-signed certificates..."

  # Validate TLS environment variables
  local missing_tls_vars=()
  [[ -z "${TLS_DIR:-}" ]] && missing_tls_vars+=("TLS_DIR")
  [[ -z "${TLS_CERT_CN:-}" ]] && missing_tls_vars+=("TLS_CERT_CN")
  [[ -z "${TLS_CERT_SANS:-}" ]] && missing_tls_vars+=("TLS_CERT_SANS")
  [[ -z "${TLS_CERT_VALIDITY_DAYS:-}" ]] && missing_tls_vars+=("TLS_CERT_VALIDITY_DAYS")
  [[ -z "${TLS_KEY_SIZE:-}" ]] && missing_tls_vars+=("TLS_KEY_SIZE")

  if [[ ${#missing_tls_vars[@]} -gt 0 ]]; then
    log_error "TLS is enabled but missing required variables: ${missing_tls_vars[*]}"
    log_info "Check your .env file and ensure all TLS_* variables are set"
    exit 2
  fi

  # Export TLS variables for the generation script
  export TLS_DIR
  export TLS_CERT_CN
  export TLS_CERT_SANS
  export TLS_CERT_VALIDITY_DAYS
  export TLS_KEY_SIZE

  # Run TLS generation script
  if [[ -x "${SCRIPT_DIR}/generate-selfsigned-tls.sh" ]]; then
    "${SCRIPT_DIR}/generate-selfsigned-tls.sh"
  else
    log_error "TLS generation script not found or not executable: ${SCRIPT_DIR}/generate-selfsigned-tls.sh"
    exit 4
  fi

  log_success "TLS certificate generation completed"
}

# Set ownership and permissions
set_permissions() {
  log_info "Setting ownership and permissions..."

  # Set appropriate ownership for each component
  # Grafana runs as UID 472
  chown -R 472:472 "${OBS_BASE_DIR}/grafana/data"

  # InfluxDB runs as UID 1000
  chown -R 1000:1000 "${OBS_BASE_DIR}/influxdb"

  # Loki runs as UID 10001
  chown -R 10001:10001 "${OBS_BASE_DIR}/loki/data"

  # Prometheus runs as nobody (UID 65534)
  chown -R 65534:65534 "${OBS_BASE_DIR}/prometheus/data"

  # Alloy runs as root (needs journal access)
  chown -R 0:0 "${OBS_BASE_DIR}/alloy"

  # Set permissions
  chmod -R 755 "${OBS_BASE_DIR}"

  # Config directories readable
  find "${OBS_BASE_DIR}" -type d \( -name "config" -o -name "provisioning" \) -print0 |
    xargs -0 chmod 755

  # TLS certificate permissions (if TLS is enabled)
  if [[ "${TLS_ENABLED:-false}" == "true" && -d "${TLS_DIR:-}" ]]; then
    if [[ -f "${TLS_DIR}/grafana.key" ]]; then
      chmod 600 "${TLS_DIR}/grafana.key"
      chown 472:472 "${TLS_DIR}/grafana.key"
    fi
    if [[ -f "${TLS_DIR}/grafana.crt" ]]; then
      chmod 644 "${TLS_DIR}/grafana.crt"
      chown 472:472 "${TLS_DIR}/grafana.crt"
    fi
  fi

  log_success "Permissions set"
}

# Apply SELinux labels
apply_selinux_labels() {
  log_info "Applying SELinux labels..."

  if ! command -v semanage &> /dev/null; then
    log_warn "semanage not found, skipping SELinux configuration"
    return 0
  fi

  # Add SELinux file context for container volumes
  if ! semanage fcontext -l | grep -q "${OBS_BASE_DIR}"; then
    semanage fcontext -a -t container_file_t "${OBS_BASE_DIR}(/.*)?"
    log_info "Added SELinux file context"
  else
    log_info "SELinux file context already exists"
  fi

  # Restore context
  restorecon -Rv "${OBS_BASE_DIR}" > /dev/null 2>&1 || true

  log_success "SELinux labels applied"
}

# Validate rendered quadlet for unresolved placeholders
validate_quadlet() {
  local file="$1"
  local filename
  filename=$(basename "${file}")

  # Check for unresolved ${VAR} or $VAR patterns (excluding Grafana's %(...)s templates)
  local unresolved_dollar
  unresolved_dollar=$(grep -E '\$\{[A-Z0-9_]+\}|\$[A-Z0-9_]+' "${file}" | grep -v '%(protocol)s\|%(domain)s\|%(http_port)s' || true)

  # Check for unresolved %VAR% patterns (old format that should never appear)
  local unresolved_percent
  unresolved_percent=$(grep -E '%[A-Z0-9_]+%' "${file}" || true)

  if [[ -n "${unresolved_dollar}" ]]; then
    log_error "Unresolved variable placeholders found in ${filename}:"
    echo "${unresolved_dollar}"
    log_error "Installation aborted - check .env file for missing required variables"
    return 1
  fi

  if [[ -n "${unresolved_percent}" ]]; then
    log_error "Old-style %VAR% placeholders found in ${filename} (should use \${VAR}):"
    echo "${unresolved_percent}"
    log_error "This indicates a bug in the quadlet template - please report this issue"
    return 1
  fi

  return 0
}

# Install Quadlet files
install_quadlets() {
  log_info "Installing Quadlet unit files..."

  # Create Quadlet directory if it doesn't exist
  mkdir -p "${QUADLET_DIR}"

  # Export all required variables for envsubst
  export GRAFANA_DOMAIN
  export GRAFANA_ADMIN_USER
  export GRAFANA_ADMIN_PASSWORD
  export GRAFANA_INSTALL_ZABBIX_PLUGIN
  export GRAFANA_INSTALL_LIBRENMS_PLUGIN
  export GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS
  export ZABBIX_URL
  export ZABBIX_API_TOKEN
  export INFLUXDB_ORG
  export INFLUXDB_BUCKET
  export INFLUXDB_TOKEN
  export INFLUXDB_ADMIN_USER
  export INFLUXDB_ADMIN_PASSWORD

  # Build plugin list dynamically
  local plugins=()
  if [[ "${GRAFANA_INSTALL_ZABBIX_PLUGIN:-false}" == "true" ]]; then
    plugins+=("alexanderzobnin-zabbix-app")
  fi

  # Join plugins with comma
  if [[ ${#plugins[@]} -gt 0 ]]; then
    GRAFANA_PLUGINS=$(
      IFS=,
      echo "${plugins[*]}"
    )
  else
    GRAFANA_PLUGINS=""
  fi
  export GRAFANA_PLUGINS

  # TLS/HTTPS configuration (conditional exports)
  if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
    export TLS_DIR
    export GF_SERVER_PROTOCOL="https"
    export GF_SERVER_CERT_FILE="/etc/grafana/tls/grafana.crt"
    export GF_SERVER_CERT_KEY="/etc/grafana/tls/grafana.key"
  else
    export TLS_DIR="/dev/null"
    export GF_SERVER_PROTOCOL="http"
    export GF_SERVER_CERT_FILE=""
    export GF_SERVER_CERT_KEY=""
  fi

  # Process each quadlet file
  for quadlet_file in "${PROJECT_ROOT}/quadlets"/*.{container,network}; do
    if [[ -f "${quadlet_file}" ]]; then
      local filename
      filename=$(basename "${quadlet_file}")
      local dest_file="${QUADLET_DIR}/${filename}"

      # Use envsubst to substitute ${VAR} format variables
      envsubst < "${quadlet_file}" > "${dest_file}"
      chmod 644 "${dest_file}"

      # Validate the rendered quadlet for unresolved placeholders
      if ! validate_quadlet "${dest_file}"; then
        log_error "Quadlet validation failed for ${filename}"
        exit 4
      fi

      # Special handling for grafana.container
      if [[ "${filename}" == "grafana.container" ]]; then
        # Handle plugin installation
        if [[ -n "${GRAFANA_PLUGINS}" ]]; then
          log_info "Enabled Grafana plugins: ${GRAFANA_PLUGINS}"
        else
          # Remove the GF_INSTALL_PLUGINS line if no plugins are enabled
          sed -i '/^Environment=GF_INSTALL_PLUGINS=/d' "${dest_file}"
          log_info "No Grafana plugins enabled"
        fi

        # Handle TLS configuration
        if [[ "${TLS_ENABLED:-false}" != "true" ]]; then
          # Remove TLS-related lines if TLS is disabled
          sed -i '/^Volume=.*\/tls:/d' "${dest_file}"
          sed -i '/^Environment=GF_SERVER_CERT_FILE=/d' "${dest_file}"
          sed -i '/^Environment=GF_SERVER_CERT_KEY=/d' "${dest_file}"
          log_info "TLS disabled - removed TLS configuration from Grafana container"
        else
          log_info "TLS enabled - Grafana will use HTTPS"
        fi
      fi

      log_info "Installed ${filename}"
    fi
  done

  log_success "Quadlet files installed and validated"
}

# Reload systemd and enable services
reload_systemd() {
  log_info "Reloading systemd daemon..."

  systemctl daemon-reload

  log_success "Systemd daemon reloaded"
}

# Pull container images
pull_images() {
  log_info "Pulling container images (this may take a while)..."

  local images=(
    "docker.io/grafana/grafana:latest"
    "docker.io/influxdb:2.7"
    "quay.io/prometheus/prometheus:latest"
    "docker.io/grafana/loki:latest"
    "docker.io/grafana/alloy:latest"
  )

  for image in "${images[@]}"; do
    log_info "Pulling ${image}..."
    if podman pull "${image}"; then
      log_success "Pulled ${image}"
    else
      log_warn "Failed to pull ${image}, will retry on container start"
    fi
  done

  log_success "Container images pulled"
}

# Enable and start services
start_services() {
  log_info "Enabling and starting services..."

  # Services in dependency order
  # Note: obs-network.network generates obs-network-network.service
  local services=(
    "obs-network-network"
    "influxdb"
    "prometheus"
    "loki"
    "alloy"
    "grafana"
  )

  for service in "${services[@]}"; do
    log_info "Enabling ${service}..."
    systemctl enable "${service}.service" 2> /dev/null || true

    log_info "Starting ${service}..."
    if systemctl start "${service}.service"; then
      log_success "${service} started"
    else
      log_error "Failed to start ${service}"
      log_info "Check logs: journalctl -u ${service}.service -n 50"
    fi

    # Wait a bit between service starts
    sleep 2
  done

  log_success "All services enabled and started"
}

# Configure firewall rules
configure_firewall() {
  local configure="${CONFIGURE_FIREWALL:-}"

  if [[ "${configure}" != "true" ]]; then
    log_info "Firewall configuration skipped (CONFIGURE_FIREWALL=${configure:-not set})"
    log_warn "Remember to manually configure firewall rules for:"
    log_warn "  - Port 3000 (Grafana) from admin subnet"
    log_warn "  - Port 8086 (InfluxDB) from LibreNMS VM"
    return 0
  fi

  log_info "Configuring firewall rules..."

  # Check if firewalld is available
  if ! command -v firewall-cmd &> /dev/null; then
    log_warn "firewalld not found - skipping firewall configuration"
    log_warn "Please configure firewall manually"
    return 0
  fi

  if ! systemctl is-active --quiet firewalld; then
    log_warn "firewalld is not running - skipping firewall configuration"
    log_warn "Start firewalld with: systemctl start firewalld"
    return 0
  fi

  # Validate required variables
  if [[ -z "${GRAFANA_ADMIN_SUBNET:-}" ]]; then
    log_error "GRAFANA_ADMIN_SUBNET not set in .env"
    return 1
  fi

  if [[ -z "${LIBRENMS_VM_IP:-}" ]]; then
    log_error "LIBRENMS_VM_IP not set in .env"
    return 1
  fi

  # Validate CIDR format for admin subnet
  if [[ ! "${GRAFANA_ADMIN_SUBNET}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_error "Invalid GRAFANA_ADMIN_SUBNET format: ${GRAFANA_ADMIN_SUBNET}"
    log_error "Expected format: 10.1.10.0/24"
    return 1
  fi

  # Validate IP format for LibreNMS
  if [[ ! "${LIBRENMS_VM_IP}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Invalid LIBRENMS_VM_IP format: ${LIBRENMS_VM_IP}"
    log_error "Expected format: 10.2.2.100"
    return 1
  fi

  # Configure Grafana access (port 3000)
  log_info "Allowing Grafana access (port 3000) from ${GRAFANA_ADMIN_SUBNET}..."
  firewall-cmd --permanent \
    --add-rich-rule="rule family=\"ipv4\" source address=\"${GRAFANA_ADMIN_SUBNET}\" port port=\"3000\" protocol=\"tcp\" accept" \
    2> /dev/null || log_warn "Grafana firewall rule may already exist"

  # Configure InfluxDB access (port 8086)
  log_info "Allowing InfluxDB access (port 8086) from ${LIBRENMS_VM_IP}..."
  firewall-cmd --permanent \
    --add-rich-rule="rule family=\"ipv4\" source address=\"${LIBRENMS_VM_IP}/32\" port port=\"8086\" protocol=\"tcp\" accept" \
    2> /dev/null || log_warn "InfluxDB firewall rule may already exist"

  # Reload firewall
  log_info "Reloading firewall..."
  firewall-cmd --reload

  log_success "Firewall configured successfully"
  log_info "Active firewall rules for observability stack:"
  firewall-cmd --list-rich-rules | grep -E "(3000|8086)" || log_warn "No matching rules found"
  echo ""
}

# Display status
show_status() {
  log_info "Service status:"
  echo ""

  local services=(
    "obs-network-network"
    "influxdb"
    "prometheus"
    "loki"
    "alloy"
    "grafana"
  )

  for service in "${services[@]}"; do
    if systemctl is-active --quiet "${service}.service"; then
      echo -e "${GREEN}✓${NC} ${service} is running"
    else
      echo -e "${RED}✗${NC} ${service} is not running"
    fi
  done

  echo ""
  log_info "Access points:"
  echo "  Grafana:    http://localhost:3000"
  echo "  Prometheus: http://localhost:9090 (internal)"
  echo "  Loki:       http://localhost:3100 (internal)"
  echo "  InfluxDB:   http://localhost:8086 (internal)"
  echo ""
  log_info "Default credentials:"
  echo "  Grafana:    ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}"
  echo "  InfluxDB:   ${INFLUXDB_ADMIN_USER} / ${INFLUXDB_ADMIN_PASSWORD}"
  echo ""
}

# Main installation function
main() {
  log_info "Starting Observability Stack installation..."
  echo ""

  check_root
  check_prerequisites
  load_environment
  create_directories
  copy_configurations
  generate_tls_certificates
  set_permissions
  apply_selinux_labels
  install_quadlets
  reload_systemd
  pull_images
  start_services
  configure_firewall

  echo ""
  log_success "Installation completed successfully!"
  echo ""

  show_status

  log_info "Run 'scripts/health-check.sh' to verify the deployment"
}

# Run main function
main "$@"
