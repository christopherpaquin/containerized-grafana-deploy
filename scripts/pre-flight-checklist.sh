#!/usr/bin/env bash
# pre-flight-checklist.sh - Pre-flight validation for containerized Grafana stack (Podman Quadlets on RHEL 10)
#
# Purpose:
#   - Validate environment prerequisites BEFORE running installer
#   - Validate .env contains required variables and no deprecated variables
#   - Validate basic system dependencies (podman, systemd, SELinux)
#   - Validate local port availability (does NOT validate firewall rules)
#
# Firewall note:
#   - This script does NOT verify firewalld/nftables rules.
#   - If your installer manages firewall openings, it should open:
#       - 3000/tcp (Grafana UI)
#       - 8086/tcp (InfluxDB write endpoint; typically restricted to LibreNMS VM)
#
# Usage:
#   sudo ./scripts/pre-flight-checklist.sh
#   ENV_FILE=/path/to/.env sudo ./scripts/pre-flight-checklist.sh

set -euo pipefail

# ---------- Helpers ----------
red() { printf "\033[31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
info() { printf "INFO: %s\n" "$*"; }
warn() { yellow "WARN: $*"; }
fail() {
  red "FAIL: $*"
  EXIT_CODE=1
}

have_cmd() { command -v "$1" > /dev/null 2>&1; }

# Safe env lookup without echoing secrets
env_has() {
  local k="$1"
  [[ -n "${ENV_VARS[$k]:-}" ]]
}

# Basic URL sanity
is_http_url() {
  local u="$1"
  [[ "$u" =~ ^https?:// ]]
}

# Check if a local TCP port is already in use
port_in_use() {
  local p="$1"
  if have_cmd ss; then
    ss -lnt 2> /dev/null | awk '{print $4}' | grep -Eq "[:.]$p$"
  elif have_cmd netstat; then
    netstat -lnt 2> /dev/null | awk '{print $4}' | grep -Eq "[:.]$p$"
  else
    # no tool to test; assume not in use
    return 1
  fi
}

# ---------- Main ----------
EXIT_CODE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env}"

info "Starting pre-flight checks..."
info "Using ENV_FILE: $ENV_FILE"

# ---------- Root privilege check ----------
if [[ $EUID -ne 0 ]]; then
  warn "Not running as root. Installation will require root privileges."
  warn "Consider running: sudo ./scripts/pre-flight-checklist.sh"
fi

# ---------- OS checks ----------
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Detected OS: ${PRETTY_NAME:-unknown}"
  # Prefer strict RHEL 10 family check
  if [[ "${ID:-}" != "rhel" && "${ID_LIKE:-}" != *"rhel"* && "${ID_LIKE:-}" != *"fedora"* ]]; then
    warn "OS does not appear to be RHEL-family. Proceed only if you know this is supported."
  fi
  if [[ "${VERSION_ID:-}" != 10* ]]; then
    warn "VERSION_ID is not 10.x. This project targets RHEL 10."
  fi
else
  warn "Cannot read /etc/os-release; skipping OS identification."
fi

# ---------- Command dependencies ----------
for c in podman systemctl; do
  if ! have_cmd "$c"; then
    fail "Missing required command: $c"
  fi
done

if ! have_cmd quadlet; then
  # quadlet binary may not exist; Quadlet still works via systemd generator.
  info "Command 'quadlet' not found (may be OK). Checking for Podman Quadlet generator..."
fi

# Check for systemd quadlet generator (required for Quadlet support)
QUADLET_GEN="/usr/lib/systemd/system-generators/podman-system-generator"
if [[ ! -x "$QUADLET_GEN" ]]; then
  fail "Podman Quadlet generator not found at $QUADLET_GEN"
  fail "Install podman 4.4+ with Quadlet support. Check: rpm -q podman"
else
  info "Podman Quadlet generator found: $QUADLET_GEN"
fi

if ! have_cmd curl; then
  warn "curl not found. Not required for install, but useful for post-install validation."
fi

# ---------- systemd checks ----------
if ! systemctl is-system-running > /dev/null 2>&1; then
  warn "systemd does not report a clean running state (this can happen in containers/chroots)."
fi

# ---------- SELinux checks ----------
if have_cmd getenforce; then
  SELINUX_MODE="$(getenforce || true)"
  info "SELinux: $SELINUX_MODE"
  if [[ "$SELINUX_MODE" == "Enforcing" ]]; then
    info "SELinux is enforcing (expected). Installer must apply correct labels for bind mounts."
  fi
else
  warn "getenforce not found; cannot determine SELinux status."
fi

# ---------- Load .env safely ----------
if [[ ! -f "$ENV_FILE" ]]; then
  fail "Missing $ENV_FILE. Create it by copying .env.example to .env and filling values."
else
  if [[ ! -r "$ENV_FILE" ]]; then
    fail "Cannot read $ENV_FILE (permissions)."
  fi
  # parse .env without executing arbitrary code:
  # - supports KEY=VALUE
  # - ignores comments and blank lines
  declare -A ENV_VARS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    # accept KEY=VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # Remove optional surrounding quotes (simple)
      if [[ "$val" =~ ^\".*\"$ ]]; then val="${val:1:${#val}-2}"; fi
      if [[ "$val" =~ ^\'.*\'$ ]]; then val="${val:1:${#val}-2}"; fi
      ENV_VARS["$key"]="$val"
    else
      warn "Skipping unrecognized line in .env: $line"
    fi
  done < "$ENV_FILE"
fi

# ---------- Required variables ----------
REQUIRED_VARS=(
  INFLUXDB_ADMIN_USER
  INFLUXDB_ADMIN_PASSWORD
  INFLUXDB_ORG
  INFLUXDB_BUCKET
  INFLUXDB_TOKEN

  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  GRAFANA_DOMAIN

  GRAFANA_INSTALL_ZABBIX_PLUGIN
)

CONDITIONAL_ZABBIX_VARS=(
  GRAFANA_ZABBIX_PLUGIN_ID
  GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS
  ZABBIX_URL
  ZABBIX_API_TOKEN
)

CONDITIONAL_FIREWALL_VARS=(
  GRAFANA_ADMIN_SUBNET
  LIBRENMS_VM_IP
)

DEPRECATED_VARS=(
  ZABBIX_USER
  ZABBIX_PASSWORD
)

info "Validating required environment variables..."
for k in "${REQUIRED_VARS[@]}"; do
  if ! env_has "$k"; then
    fail "Missing required env var: $k"
  else
    if [[ -z "${ENV_VARS[$k]}" ]]; then
      fail "Env var is set but empty: $k"
    fi
  fi
done

info "Checking for deprecated variables..."
for k in "${DEPRECATED_VARS[@]}"; do
  if env_has "$k"; then
    fail "Deprecated env var present in .env: $k (use ZABBIX_API_TOKEN instead)"
  fi
done

# ---------- Value sanity checks ----------
# Plugin checks
if [[ "${ENV_VARS[GRAFANA_INSTALL_ZABBIX_PLUGIN]}" != "true" && "${ENV_VARS[GRAFANA_INSTALL_ZABBIX_PLUGIN]}" != "false" ]]; then
  fail "GRAFANA_INSTALL_ZABBIX_PLUGIN must be 'true' or 'false'"
fi

# Conditional Zabbix variable validation (only if plugin enabled)
if [[ "${ENV_VARS[GRAFANA_INSTALL_ZABBIX_PLUGIN]}" == "true" ]]; then
  info "Zabbix plugin enabled - validating Zabbix variables..."

  for k in "${CONDITIONAL_ZABBIX_VARS[@]}"; do
    if ! env_has "$k"; then
      fail "Zabbix plugin enabled but missing required var: $k"
    else
      if [[ -z "${ENV_VARS[$k]}" ]]; then
        fail "Zabbix plugin enabled but var is empty: $k"
      fi
    fi
  done

  # ZABBIX_URL must be http(s) and end with /api_jsonrpc.php
  ZURL="${ENV_VARS[ZABBIX_URL]}"
  if ! is_http_url "$ZURL"; then
    fail "ZABBIX_URL must start with http:// or https://"
  fi
  if [[ "$ZURL" != */api_jsonrpc.php ]]; then
    fail "ZABBIX_URL must end with /api_jsonrpc.php"
  fi

  # Plugin ID check
  if [[ "${ENV_VARS[GRAFANA_ZABBIX_PLUGIN_ID]}" != "alexanderzobnin-zabbix-app" ]]; then
    warn "GRAFANA_ZABBIX_PLUGIN_ID is not 'alexanderzobnin-zabbix-app'. If intentional, ensure provisioning matches."
  fi

  # Trends threshold must be integer
  if ! [[ "${ENV_VARS[GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS]}" =~ ^[0-9]+$ ]]; then
    fail "GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS must be an integer (e.g., 7)"
  fi

  # Check for placeholder token
  if [[ "${ENV_VARS[ZABBIX_API_TOKEN]}" == *"changeme"* ]]; then
    fail "ZABBIX_API_TOKEN contains 'changeme' - generate a real token in Zabbix UI"
  fi
else
  info "Zabbix plugin disabled (GRAFANA_INSTALL_ZABBIX_PLUGIN=false) - skipping Zabbix validation"
fi

# Validate token strength
info "Validating token strength..."
if [[ ${#ENV_VARS[INFLUXDB_TOKEN]} -lt 32 ]]; then
  warn "INFLUXDB_TOKEN is shorter than 32 characters. Recommended: openssl rand -base64 32"
fi
if [[ "${ENV_VARS[INFLUXDB_TOKEN]}" == *"changeme"* ]]; then
  fail "INFLUXDB_TOKEN contains 'changeme' - generate a real token with: openssl rand -base64 32"
fi

# Password strength checks
for pw_var in INFLUXDB_ADMIN_PASSWORD GRAFANA_ADMIN_PASSWORD; do
  if [[ ${#ENV_VARS[$pw_var]} -lt 16 ]]; then
    warn "$pw_var is shorter than 16 characters. Recommended minimum: 16 characters"
  fi
  if [[ "${ENV_VARS[$pw_var]}" == *"changeme"* ]]; then
    fail "$pw_var contains 'changeme' - use a strong password"
  fi
done

# Optional InfluxDB external URL variables (documentation only)
if env_has INFLUXDB_URL; then
  if ! is_http_url "${ENV_VARS[INFLUXDB_URL]}"; then
    fail "INFLUXDB_URL must start with http:// or https://"
  fi
fi
if env_has INFLUXDB_PORT; then
  if ! [[ "${ENV_VARS[INFLUXDB_PORT]}" =~ ^[0-9]+$ ]]; then
    fail "INFLUXDB_PORT must be numeric"
  fi
fi

# Conditional firewall variable validation (only if enabled)
if env_has CONFIGURE_FIREWALL; then
  if [[ "${ENV_VARS[CONFIGURE_FIREWALL]}" == "true" ]]; then
    info "Firewall automation enabled - validating firewall variables..."

    for k in "${CONDITIONAL_FIREWALL_VARS[@]}"; do
      if ! env_has "$k"; then
        fail "CONFIGURE_FIREWALL=true but missing required var: $k"
      else
        if [[ -z "${ENV_VARS[$k]}" ]]; then
          fail "CONFIGURE_FIREWALL=true but var is empty: $k"
        fi
      fi
    done

    # Validate CIDR format for GRAFANA_ADMIN_SUBNET
    if ! [[ "${ENV_VARS[GRAFANA_ADMIN_SUBNET]}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      fail "GRAFANA_ADMIN_SUBNET must be in CIDR format (e.g., 10.1.10.0/24)"
    fi

    # Validate IP format for LIBRENMS_VM_IP
    if ! [[ "${ENV_VARS[LIBRENMS_VM_IP]}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      fail "LIBRENMS_VM_IP must be a valid IP address (e.g., 10.2.2.100)"
    fi
  else
    info "Firewall automation disabled - skipping firewall variable validation"
  fi
else
  info "CONFIGURE_FIREWALL not set - firewall rules will need manual configuration"
fi

# ---------- Local port availability checks (not firewall checks) ----------
# These ports are expected to be published by the installer:
#   3000 (Grafana)
#   8086 (InfluxDB, for LibreNMS -> Influx writes)
info "Checking local port availability (does not validate firewall rules)..."
for p in 3000 8086; do
  if port_in_use "$p"; then
    fail "Local TCP port $p appears to be in use. Stop the conflicting service or change port mapping."
  fi
done

# ---------- Directory permissions / disk sanity ----------
# If you have a standard bind-mount root, validate it (non-fatal if not created yet).
BIND_ROOT="/srv/obs"
if [[ -d "$BIND_ROOT" ]]; then
  info "Bind-mount root exists: $BIND_ROOT"
  if [[ ! -w "$BIND_ROOT" ]]; then
    warn "$BIND_ROOT is not writable by current user. Installer requires root (expected)."
  fi
else
  info "Bind-mount root does not exist yet ($BIND_ROOT). Installer will create it."
fi

# Check disk space on /srv (where data will be stored)
MOUNT_POINT="/srv"
if have_cmd df; then
  AVAIL_KB="$(df -Pk "$MOUNT_POINT" 2> /dev/null | awk 'NR==2 {print $4}')"
  if [[ -n "$AVAIL_KB" ]] && [[ "$AVAIL_KB" =~ ^[0-9]+$ ]]; then
    AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
    info "Available space on $MOUNT_POINT: ${AVAIL_GB}GB"

    # Warn if less than 500GB (recommended for 1-year retention with 200 devices)
    if ((AVAIL_KB < 500 * 1024 * 1024)); then
      warn "Less than 500GB free on $MOUNT_POINT"
      warn "Recommended: 500GB+ for 1-year retention with 200 devices"
      warn "Current baseline: InfluxDB(150GB) + Prometheus(200GB) + Loki(100GB) + overhead"
    fi

    # Fail if critically low (< 50GB)
    if ((AVAIL_KB < 50 * 1024 * 1024)); then
      fail "Less than 50GB free on $MOUNT_POINT - insufficient for deployment"
    fi
  fi
fi

# ---------- Summary ----------
if ((EXIT_CODE == 0)); then
  green "Pre-flight checks passed."
  info "Reminder: Firewall rules are expected to be configured by the installer."
  info "Installer should open/publish: 3000/tcp (Grafana), 8086/tcp (InfluxDB; restricted to LibreNMS VM)."
else
  red "Pre-flight checks failed. Fix the issues above before running the installer."
fi

exit "$EXIT_CODE"
