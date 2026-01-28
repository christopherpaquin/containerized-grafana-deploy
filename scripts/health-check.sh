#!/usr/bin/env bash
#
# Observability Stack Health Check Script
# Verifies all components are running and healthy
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
readonly TIMEOUT=5

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $*"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $*"
  WARNING_CHECKS=$((WARNING_CHECKS + 1))
}

# Check if a service is running
check_service() {
  local service=$1
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if systemctl is-active --quiet "${service}.service" 2> /dev/null; then
    log_success "Service ${service} is running"
    return 0
  else
    log_fail "Service ${service} is not running"
    return 1
  fi
}

# Check if a container is running
check_container() {
  local container=$1
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if podman container exists "${container}" 2> /dev/null; then
    local state
    state=$(podman inspect --format='{{.State.Status}}' "${container}" 2> /dev/null)

    if [[ "${state}" == "running" ]]; then
      log_success "Container ${container} is running"
      return 0
    else
      log_fail "Container ${container} exists but is not running (state: ${state})"
      return 1
    fi
  else
    log_fail "Container ${container} does not exist"
    return 1
  fi
}

# Check HTTP endpoint
check_http_endpoint() {
  local name=$1
  local url=$2
  local expected_code=${3:-200}

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  local response_code
  if response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" "${url}" 2> /dev/null); then
    if [[ "${response_code}" -eq "${expected_code}" ]]; then
      log_success "${name} endpoint is healthy (HTTP ${response_code})"
      return 0
    else
      log_fail "${name} returned HTTP ${response_code}, expected ${expected_code}"
      return 1
    fi
  else
    log_fail "${name} endpoint is unreachable at ${url}"
    return 1
  fi
}

# Check directory exists and is writable
check_directory() {
  local name=$1
  local path=$2

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if [[ ! -d "${path}" ]]; then
    log_fail "${name} directory does not exist: ${path}"
    return 1
  fi

  if [[ ! -w "${path}" ]]; then
    log_warn "${name} directory is not writable: ${path}"
    return 1
  fi

  log_success "${name} directory exists and is writable"
  return 0
}

# Check disk usage
check_disk_usage() {
  local path=$1
  local threshold=${2:-90}

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if [[ ! -d "${path}" ]]; then
    log_warn "Cannot check disk usage, path does not exist: ${path}"
    return 1
  fi

  local usage
  usage=$(df -h "${path}" | awk 'NR==2 {print $5}' | sed 's/%//')

  if [[ ${usage} -ge ${threshold} ]]; then
    log_warn "Disk usage is ${usage}% (threshold: ${threshold}%) for ${path}"
    return 1
  else
    log_success "Disk usage is ${usage}% for ${path}"
    return 0
  fi
}

# Check Podman network
check_network() {
  local network=$1

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if podman network exists "${network}" 2> /dev/null; then
    log_success "Podman network ${network} exists"
    return 0
  else
    log_fail "Podman network ${network} does not exist"
    return 1
  fi
}

# Check container resource usage
check_container_resources() {
  local container=$1

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if ! podman container exists "${container}" 2> /dev/null; then
    log_warn "Cannot check resources, container ${container} does not exist"
    return 1
  fi

  local stats
  if stats=$(podman stats --no-stream --format "{{.MemPerc}}" "${container}" 2> /dev/null); then
    log_success "Container ${container} resource usage: Memory ${stats}"
    return 0
  else
    log_warn "Could not retrieve stats for ${container}"
    return 1
  fi
}

# Check if a configuration file exists
check_config_file() {
  local name=$1
  local path=$2

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if [[ -f "${path}" ]]; then
    log_success "${name} configuration file exists"
    return 0
  else
    log_fail "${name} configuration file missing: ${path}"
    return 1
  fi
}

# Check if a port is listening
check_port_listening() {
  local name=$1
  local port=$2

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if command -v ss > /dev/null 2>&1; then
    if ss -lnt 2> /dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
      log_success "${name} is listening on port ${port}"
      return 0
    else
      log_fail "${name} is not listening on port ${port}"
      return 1
    fi
  elif command -v netstat > /dev/null 2>&1; then
    if netstat -lnt 2> /dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
      log_success "${name} is listening on port ${port}"
      return 0
    else
      log_fail "${name} is not listening on port ${port}"
      return 1
    fi
  else
    log_warn "Cannot check port ${port}, neither ss nor netstat available"
    return 1
  fi
}

# Check SELinux labels
check_selinux_label() {
  local name=$1
  local path=$2
  local expected_label="container_file_t"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if ! command -v getenforce > /dev/null 2>&1; then
    log_warn "SELinux tools not available, skipping label check for ${name}"
    return 1
  fi

  if [[ "$(getenforce 2> /dev/null)" == "Disabled" ]]; then
    log_warn "SELinux is disabled, skipping label check for ${name}"
    return 1
  fi

  if [[ ! -e "${path}" ]]; then
    log_warn "Cannot check SELinux label, path does not exist: ${path}"
    return 1
  fi

  local label
  # shellcheck disable=SC2012
  label=$(ls -Zd "${path}" 2> /dev/null | awk '{print $1}' | cut -d: -f3)

  if [[ "${label}" == "${expected_label}" ]]; then
    log_success "${name} has correct SELinux label (${expected_label})"
    return 0
  else
    log_fail "${name} has incorrect SELinux label: ${label} (expected: ${expected_label})"
    return 1
  fi
}

# Check if Quadlet file exists
check_quadlet_file() {
  local name=$1
  local filename=$2

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  local quadlet_path="/etc/containers/systemd/${filename}"

  if [[ -f "${quadlet_path}" ]]; then
    log_success "Quadlet file ${filename} exists"
    return 0
  else
    log_fail "Quadlet file ${filename} missing: ${quadlet_path}"
    return 1
  fi
}

# Check firewall rules (if firewalld is active)
check_firewall_rule() {
  local port=$1
  local description=$2

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if ! command -v firewall-cmd > /dev/null 2>&1; then
    log_warn "firewalld not installed, skipping firewall check for ${description}"
    return 1
  fi

  if ! systemctl is-active --quiet firewalld; then
    log_warn "firewalld not running, skipping firewall check for ${description}"
    return 1
  fi

  if firewall-cmd --list-rich-rules 2> /dev/null | grep -q "port=\"${port}\""; then
    log_success "Firewall rule exists for ${description} (port ${port})"
    return 0
  else
    log_warn "No firewall rule found for ${description} (port ${port})"
    return 1
  fi
}

# Check Grafana datasources via API
check_grafana_datasources() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  local datasources
  if datasources=$(curl -s --max-time "${TIMEOUT}" "http://localhost:3000/api/datasources" 2> /dev/null); then
    local count
    count=$(echo "${datasources}" | grep -o '"name"' | wc -l)

    if [[ ${count} -ge 3 ]]; then
      log_success "Grafana has ${count} datasources provisioned"
      return 0
    else
      log_warn "Grafana has only ${count} datasources (expected at least 3)"
      return 1
    fi
  else
    log_warn "Cannot query Grafana datasources API"
    return 1
  fi
}

# Check InfluxDB organization and bucket
check_influxdb_resources() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  local health
  if health=$(curl -s --max-time "${TIMEOUT}" "http://localhost:8086/health" 2> /dev/null); then
    if echo "${health}" | grep -q '"status":"pass"'; then
      log_success "InfluxDB is initialized and healthy"
      return 0
    else
      log_warn "InfluxDB health check did not return pass status"
      return 1
    fi
  else
    log_fail "Cannot query InfluxDB health endpoint"
    return 1
  fi
}

# Check Grafana plugins
check_grafana_plugin() {
  local plugin_id=$1

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if podman exec grafana grafana-cli plugins ls 2> /dev/null | grep -q "${plugin_id}"; then
    log_success "Grafana plugin ${plugin_id} is installed"
    return 0
  else
    log_warn "Grafana plugin ${plugin_id} not found"
    return 1
  fi
}

# Check service logs for errors
check_service_logs() {
  local service=$1

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  if ! systemctl is-active --quiet "${service}.service" 2> /dev/null; then
    log_warn "Cannot check logs, ${service} service is not running"
    return 1
  fi

  local error_count
  error_count=$(journalctl -u "${service}.service" -n 100 --no-pager 2> /dev/null | grep -icE "error|fatal|failed" || echo "0")

  if [[ ${error_count} -eq 0 ]]; then
    log_success "${service} logs show no recent errors"
    return 0
  else
    log_warn "${service} has ${error_count} error/warning messages in recent logs"
    return 1
  fi
}

# Print header
print_header() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║       Observability Stack Health Check Report             ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
}

# Print summary
print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                    Summary                                  ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo -e "  Total checks:   ${TOTAL_CHECKS}"
  echo -e "  ${GREEN}✓ Passed:${NC}      ${PASSED_CHECKS}"
  echo -e "  ${RED}✗ Failed:${NC}      ${FAILED_CHECKS}"
  echo -e "  ${YELLOW}⚠ Warnings:${NC}    ${WARNING_CHECKS}"
  echo ""

  if [[ ${FAILED_CHECKS} -eq 0 ]]; then
    echo -e "${GREEN}Overall Status: HEALTHY${NC}"
    echo ""
    return ${EXIT_SUCCESS}
  else
    echo -e "${RED}Overall Status: UNHEALTHY${NC}"
    echo ""
    echo "Troubleshooting commands:"
    echo "  - View service logs:    journalctl -u <service-name> -n 50"
    echo "  - Check container logs: podman logs <container-name>"
    echo "  - Service status:       systemctl status <service-name>"
    echo ""
    return ${EXIT_FAILURE}
  fi
}

# Main health check function
main() {
  print_header

  # Check if running as root (some checks require it)
  if [[ "${EUID}" -ne 0 ]]; then
    log_warn "Not running as root, some checks may be limited"
  fi

  # 1. Check systemd services
  log_info "Checking systemd services..."
  check_service "obs-network"
  check_service "influxdb"
  check_service "prometheus"
  check_service "loki"
  check_service "alloy"
  check_service "grafana"
  echo ""

  # 2. Check containers
  log_info "Checking containers..."
  check_container "influxdb"
  check_container "prometheus"
  check_container "loki"
  check_container "alloy"
  check_container "grafana"
  echo ""

  # 3. Check Podman network
  log_info "Checking Podman network..."
  check_network "obs-net"
  echo ""

  # 4. Check bind mount directories
  log_info "Checking bind mount directories..."
  check_directory "Grafana data" "${OBS_BASE_DIR}/grafana/data"
  check_directory "InfluxDB data" "${OBS_BASE_DIR}/influxdb/data"
  check_directory "Prometheus data" "${OBS_BASE_DIR}/prometheus/data"
  check_directory "Loki data" "${OBS_BASE_DIR}/loki/data"
  check_directory "Alloy data" "${OBS_BASE_DIR}/alloy/data"
  echo ""

  # 5. Check HTTP health endpoints
  log_info "Checking HTTP endpoints..."
  check_http_endpoint "Grafana" "http://localhost:3000/api/health"
  check_http_endpoint "Prometheus" "http://localhost:9090/-/healthy"
  check_http_endpoint "Loki" "http://localhost:3100/ready"
  check_http_endpoint "InfluxDB" "http://localhost:8086/health"
  echo ""

  # 6. Check disk usage
  log_info "Checking disk usage..."
  check_disk_usage "${OBS_BASE_DIR}" 90
  echo ""

  # 7. Check container resources (if running as root)
  if [[ "${EUID}" -eq 0 ]]; then
    log_info "Checking container resource usage..."
    check_container_resources "grafana"
    check_container_resources "influxdb"
    check_container_resources "prometheus"
    check_container_resources "loki"
    check_container_resources "alloy"
    echo ""
  fi

  # 8. Check configuration directories
  log_info "Checking configuration directories..."
  check_directory "Prometheus config" "${OBS_BASE_DIR}/prometheus/config"
  check_directory "Loki config" "${OBS_BASE_DIR}/loki/config"
  check_directory "Alloy config" "${OBS_BASE_DIR}/alloy/config"
  check_directory "Grafana provisioning" "${OBS_BASE_DIR}/grafana/provisioning"
  echo ""

  # 9. Check configuration files
  log_info "Checking configuration files..."
  check_config_file "Prometheus" "${OBS_BASE_DIR}/prometheus/config/prometheus.yml"
  check_config_file "Loki" "${OBS_BASE_DIR}/loki/config/loki.yaml"
  check_config_file "Alloy" "${OBS_BASE_DIR}/alloy/config/config.alloy"
  check_config_file "Grafana datasources" "${OBS_BASE_DIR}/grafana/provisioning/datasources/datasources.yaml"
  check_config_file "Grafana plugins" "${OBS_BASE_DIR}/grafana/provisioning/plugins/plugins.yaml"
  echo ""

  # 10. Check port listening status
  log_info "Checking port listening status..."
  check_port_listening "Grafana" "3000"
  check_port_listening "InfluxDB" "8086"
  check_port_listening "Prometheus" "9090"
  check_port_listening "Loki" "3100"
  echo ""

  # 11. Check SELinux labels (if SELinux is enabled)
  if command -v getenforce > /dev/null 2>&1 && [[ "$(getenforce 2> /dev/null)" != "Disabled" ]]; then
    log_info "Checking SELinux labels..."
    check_selinux_label "Grafana data" "${OBS_BASE_DIR}/grafana"
    check_selinux_label "InfluxDB data" "${OBS_BASE_DIR}/influxdb"
    check_selinux_label "Prometheus data" "${OBS_BASE_DIR}/prometheus"
    check_selinux_label "Loki data" "${OBS_BASE_DIR}/loki"
    check_selinux_label "Alloy data" "${OBS_BASE_DIR}/alloy"
    echo ""
  fi

  # 12. Check Quadlet files
  log_info "Checking Quadlet files..."
  check_quadlet_file "Network" "obs-network.network"
  check_quadlet_file "Grafana" "grafana.container"
  check_quadlet_file "InfluxDB" "influxdb.container"
  check_quadlet_file "Prometheus" "prometheus.container"
  check_quadlet_file "Loki" "loki.container"
  check_quadlet_file "Alloy" "alloy.container"
  echo ""

  # 13. Check firewall rules (if firewalld is active)
  if command -v firewall-cmd > /dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log_info "Checking firewall rules..."
    check_firewall_rule "3000" "Grafana"
    check_firewall_rule "8086" "InfluxDB"
    echo ""
  fi

  # 14. Check Grafana datasources
  log_info "Checking Grafana datasources..."
  check_grafana_datasources
  echo ""

  # 15. Check InfluxDB initialization
  log_info "Checking InfluxDB initialization..."
  check_influxdb_resources
  echo ""

  # 16. Check Grafana plugins (if Grafana is running)
  if podman container exists grafana 2> /dev/null; then
    log_info "Checking Grafana plugins..."
    check_grafana_plugin "alexanderzobnin-zabbix-app"
    echo ""
  fi

  # 17. Check service logs for errors
  log_info "Checking service logs for errors..."
  check_service_logs "grafana"
  check_service_logs "influxdb"
  check_service_logs "prometheus"
  check_service_logs "loki"
  check_service_logs "alloy"
  echo ""

  # Print summary and exit
  print_summary
}

# Run main function
main "$@"
