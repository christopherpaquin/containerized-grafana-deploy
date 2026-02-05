#!/usr/bin/env bash
#
# Self-Signed TLS Certificate Generator for Grafana
# Generates a 10-year RSA 4096 SHA-256 certificate with SANs
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

# Check if running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

# Validate required environment variables
validate_environment() {
  log_info "Validating environment variables..."

  local missing_vars=()

  # Required variables
  [[ -z "${TLS_DIR:-}" ]] && missing_vars+=("TLS_DIR")
  [[ -z "${TLS_CERT_CN:-}" ]] && missing_vars+=("TLS_CERT_CN")
  [[ -z "${TLS_CERT_SANS:-}" ]] && missing_vars+=("TLS_CERT_SANS")
  [[ -z "${TLS_CERT_VALIDITY_DAYS:-}" ]] && missing_vars+=("TLS_CERT_VALIDITY_DAYS")
  [[ -z "${TLS_KEY_SIZE:-}" ]] && missing_vars+=("TLS_KEY_SIZE")

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Missing required environment variables: ${missing_vars[*]}"
    log_info "Ensure these are defined in your .env file"
    exit 2
  fi

  log_success "Environment variables validated"
}

# Check if certificate exists and is valid
check_certificate_validity() {
  local cert_file="${TLS_DIR}/grafana.crt"
  local key_file="${TLS_DIR}/grafana.key"

  # If either file is missing, need to generate
  if [[ ! -f "${cert_file}" ]] || [[ ! -f "${key_file}" ]]; then
    return 1
  fi

  # Check if certificate is valid
  if ! openssl x509 -in "${cert_file}" -noout -checkend 2592000 &> /dev/null; then
    log_warn "Certificate expires within 30 days"
    return 1
  fi

  # Verify key matches certificate
  local cert_modulus
  local key_modulus
  cert_modulus=$(openssl x509 -noout -modulus -in "${cert_file}" 2> /dev/null | openssl md5)
  key_modulus=$(openssl rsa -noout -modulus -in "${key_file}" 2> /dev/null | openssl md5)

  if [[ "${cert_modulus}" != "${key_modulus}" ]]; then
    log_warn "Certificate and key do not match"
    return 1
  fi

  return 0
}

# Display certificate information
display_certificate_info() {
  local cert_file="${TLS_DIR}/grafana.crt"

  if [[ ! -f "${cert_file}" ]]; then
    return
  fi

  log_info "Certificate details:"

  local subject
  subject=$(openssl x509 -in "${cert_file}" -noout -subject | sed 's/subject=//')
  echo "  Subject: ${subject}"

  local issuer
  issuer=$(openssl x509 -in "${cert_file}" -noout -issuer | sed 's/issuer=//')
  echo "  Issuer: ${issuer}"

  local not_before
  not_before=$(openssl x509 -in "${cert_file}" -noout -startdate | sed 's/notBefore=//')
  echo "  Valid From: ${not_before}"

  local not_after
  not_after=$(openssl x509 -in "${cert_file}" -noout -enddate | sed 's/notAfter=//')
  echo "  Valid Until: ${not_after}"

  # Display SANs
  local sans
  sans=$(openssl x509 -in "${cert_file}" -noout -ext subjectAltName 2> /dev/null | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/^ *//' || echo "None")
  echo "  SANs: ${sans}"

  # Calculate days until expiry
  local expiry_epoch
  expiry_epoch=$(date -d "${not_after}" +%s)
  local now_epoch
  now_epoch=$(date +%s)
  local days_remaining=$(((expiry_epoch - now_epoch) / 86400))
  echo "  Days Remaining: ${days_remaining}"
}

# Create TLS directory
create_tls_directory() {
  log_info "Creating TLS directory..."

  if [[ ! -d "${TLS_DIR}" ]]; then
    mkdir -p "${TLS_DIR}"
    chmod 755 "${TLS_DIR}"
    log_success "Created ${TLS_DIR}"
  else
    log_info "Directory ${TLS_DIR} already exists"
  fi
}

# Generate OpenSSL configuration file
generate_openssl_config() {
  local config_file="${TLS_DIR}/openssl.cnf"

  log_info "Generating OpenSSL configuration..."

  cat > "${config_file}" << EOF
[req]
default_bits = ${TLS_KEY_SIZE}
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Lab
L = Lab
O = Lab
OU = Observability
CN = ${TLS_CERT_CN}

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
EOF

  # Parse and add SANs
  local index=1
  IFS=',' read -ra SANS <<< "${TLS_CERT_SANS}"
  for san in "${SANS[@]}"; do
    # Trim whitespace
    san=$(echo "${san}" | xargs)

    # Remove any existing DNS: or IP: prefix
    san="${san#DNS:}"
    san="${san#IP:}"

    # Determine if it's a DNS name or IP address
    if [[ "${san}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "IP.${index} = ${san}" >> "${config_file}"
    else
      echo "DNS.${index} = ${san}" >> "${config_file}"
    fi
    ((index++))
  done

  log_success "OpenSSL configuration created"
}

# Generate self-signed certificate
generate_certificate() {
  local cert_file="${TLS_DIR}/grafana.crt"
  local key_file="${TLS_DIR}/grafana.key"
  local config_file="${TLS_DIR}/openssl.cnf"

  log_info "Generating self-signed certificate..."
  log_info "  CN: ${TLS_CERT_CN}"
  log_info "  Key Size: ${TLS_KEY_SIZE} bits"
  log_info "  Validity: ${TLS_CERT_VALIDITY_DAYS} days"
  log_info "  SANs: ${TLS_CERT_SANS}"

  # Generate certificate and key
  openssl req \
    -x509 \
    -nodes \
    -days "${TLS_CERT_VALIDITY_DAYS}" \
    -newkey "rsa:${TLS_KEY_SIZE}" \
    -keyout "${key_file}" \
    -out "${cert_file}" \
    -config "${config_file}" \
    -sha256 \
    &> /dev/null

  # Set restrictive permissions
  chmod 600 "${key_file}"
  chmod 644 "${cert_file}"

  # Set ownership to Grafana UID (472)
  chown 472:472 "${key_file}" "${cert_file}"

  # Remove temporary config file
  rm -f "${config_file}"

  log_success "Certificate generated successfully"
}

# Main function
main() {
  log_info "Starting TLS certificate generation..."
  echo ""

  check_root
  validate_environment
  create_tls_directory

  # Check if certificate is valid and up-to-date
  if check_certificate_validity; then
    log_success "Valid certificate already exists"
    echo ""
    display_certificate_info
    log_info "No action needed - certificate is valid and not near expiry"
    exit 0
  fi

  # Generate new certificate
  log_warn "Certificate missing, invalid, or near expiry - regenerating..."
  generate_openssl_config
  generate_certificate

  echo ""
  display_certificate_info
  echo ""
  log_success "TLS certificate generation completed successfully!"
}

# Run main function
main "$@"
