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

  # Print summary and exit
  print_summary
}

# Run main function
main "$@"
