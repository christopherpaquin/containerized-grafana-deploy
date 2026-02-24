# 🔭 Containerized Grafana Observability Stack

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![RHEL 10](https://img.shields.io/badge/RHEL-10-red.svg)](https://www.redhat.com/en/enterprise-linux-10)
[![Podman](https://img.shields.io/badge/Podman-4.x-892CA0.svg)](https://podman.io/)
[![Tested](https://img.shields.io/badge/Tested%20on-RHEL%2010-success.svg)](https://www.redhat.com/)

A production-grade observability stack for RHEL 10, deploying Grafana, InfluxDB, Prometheus, Loki,
and Alloy using Podman Quadlets (systemd-managed containers).

---

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [✨ Features](#-features)
- [🏗️ Architecture](#️-architecture)
- [📦 Components](#-components)
- [⚙️ Prerequisites](#️-prerequisites)
- [🚀 Installation](#-installation)
- [🔧 Configuration](#-configuration)
- [🔌 Integration Setup](#-integration-setup)
- [✅ Health Check](#-health-check)
- [🗑️ Uninstallation](#️-uninstallation)
- [🔍 Troubleshooting](#-troubleshooting)
- [📊 Tuning and Scaling](#-tuning-and-scaling)
- [🔒 Security](#-security)
- [📚 Documentation](#-documentation)
- [📄 License](#-license)

---

## 🎯 Overview

This project provides a complete, production-ready observability stack that unifies monitoring data
from **Zabbix**, **LibreNMS**, and **Prometheus** into a single **Grafana** visualization platform,
with centralized logging via **Loki**.

### Key Highlights

- ✅ **Podman Quadlets** - Systemd-managed containers (no Docker, no docker-compose)
- ✅ **Idempotent** - Safe to run installation multiple times
- ✅ **SELinux Enforcing** - Production-grade security
- ✅ **Bind Mounts** - Persistent data storage under `/srv/obs`
- ✅ **1-Year Retention** - Configured for long-term data storage
- ✅ **RHEL 10 Native** - Built for Red Hat Enterprise Linux 10

### Tested On

| Platform | Version | Status |
|----------|---------|--------|
| RHEL 10  | 10.x    | ✅ Tested |
| CentOS Stream | 9 | ⚠️ Should work (not tested) |

---

## ✨ Features

### 🔭 Unified Observability

- **Single pane of glass** for all monitoring data
- Integrates existing Zabbix and LibreNMS deployments
- Prometheus-based metrics collection
- Centralized log aggregation with Loki

### 🛡️ Production-Ready

- SELinux enforcing mode support
- Systemd service management
- Automatic container updates
- Health checks and monitoring
- Resource limits and quotas

### 🚀 Easy Deployment

- One-command installation
- Idempotent and safe to re-run
- Clean uninstallation with data preservation option
- Comprehensive health checking

### 📊 Data Sources

- **Zabbix** - Via API and optional direct database access
- **LibreNMS** - Via InfluxDB push integration
- **Prometheus** - Native scraping of exporters
- **Loki** - Systemd journal log collection

---

## 🏗️ Architecture

### High-Level Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         Grafana VM (RHEL 10)                        │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │              Podman Network: obs-net (bridge)                  │ │
│  │                                                                 │ │
│  │   ┌──────────┐   ┌───────────┐   ┌──────────┐   ┌─────────┐ │ │
│  │   │ 🎨       │   │ 💾        │   │ 📊       │   │ 📝      │ │ │
│  │   │ Grafana  │◄─►│ InfluxDB  │◄─►│Prometheus│◄─►│  Loki   │ │ │
│  │   │  :3000   │   │  :8086    │   │  :9090   │   │  :3100  │ │ │
│  │   └────┬─────┘   └─────▲─────┘   └────▲─────┘   └────▲────┘ │ │
│  │        │               │               │               │       │ │
│  │        │               │               │          ┌────┴────┐ │ │
│  │        │               │               │          │ 🔄      │ │ │
│  │        │               │               │          │  Alloy  │ │ │
│  │        │               │               │          │ (agent) │ │ │
│  │        │               │               │          └─────────┘ │ │
│  └────────┼───────────────┼───────────────┼─────────────────────┘ │
│           │               │               │                         │
│      /srv/obs/*      /srv/obs/*      /srv/obs/*                   │
│      (bind mounts with SELinux labels)                             │
└───────────┼───────────────┼────────────────────────────────────────┘
            │               │
       ┌────▼─────┐    ┌───▼──────────┐
       │ 📡       │    │ 📡           │
       │ Zabbix   │    │  LibreNMS    │
       │    VM    │    │      VM      │
       │  (API +  │    │  (MariaDB)   │
       │   DB)    │    │              │
       └──────────┘    └──────┬───────┘
                              │
                    Metrics Push ──────┐
                    via InfluxDB API   │
                                       ▼
```

### Data Flow

```text
External Systems → Grafana Stack → Visualization
─────────────────────────────────────────────────

Zabbix VM
  ├─ API ──────────────► Grafana (alexanderzobnin-zabbix-app plugin)
  └─ MariaDB (optional)─► Grafana (direct DB queries for history)

LibreNMS VM
  └─ Metrics Push ──────► InfluxDB ──► Grafana (Flux queries)

Exporters (future)
  └─ Metrics Scrape ────► Prometheus ──► Grafana

Host System
  └─ Systemd Journal ───► Alloy ──► Loki ──► Grafana
```

---

## 📦 Components

| Component | Purpose | Port | Exposure |
|-----------|---------|------|----------|
| **Grafana** | Visualization & dashboards | 3000 | ✅ Public |
| **InfluxDB 2.x** | LibreNMS metrics storage | 8086 | ❌ Internal |
| **Prometheus** | Metrics collection & storage | 9090 | 🔧 Configurable |
| **Loki** | Log aggregation & storage | 3100 | ❌ Internal |
| **Alloy** | Log & metrics agent | - | ❌ Internal |

### Container Images

| Component | Image | Base OS |
|-----------|-------|---------|
| Grafana | `docker.io/grafana/grafana:latest` | Ubuntu |
| InfluxDB | `docker.io/influxdb:2.7` | Debian |
| Prometheus | `quay.io/prometheus/prometheus:latest` | Alpine\* |
| Loki | `docker.io/grafana/loki:latest` | Alpine\* |
| Alloy | `docker.io/grafana/alloy:latest` | Alpine\* |

\*Alpine images are acceptable per project requirements when CentOS Stream 9 or RHEL UBI alternatives
are not available.

---

## ⚙️ Prerequisites

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **OS** | RHEL 10 | RHEL 10 |
| **CPU** | 4 vCPU | 8 vCPU |
| **RAM** | 16 GB | 24 GB |
| **Disk** | 250 GB | 500 GB SSD |
| **Network** | 1 Gbps | 10 Gbps |

### Software Dependencies

```bash
# Required packages
- podman >= 4.0
- systemd >= 252
- policycoreutils-python-utils (for semanage)
- container-selinux

# Optional but recommended
- curl (for health checks)
- openssl (for token generation)
```

### Installation Checklist

- [ ] RHEL 10 system with root access
- [ ] Podman installed and configured
- [ ] SELinux in enforcing mode
- [ ] Firewall configured (ports 3000, 8086, and optionally 9090 restricted to trusted sources)
- [ ] Network connectivity to Zabbix and LibreNMS VMs
- [ ] At least 500 GB available in `/srv`

---

## 🚀 Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/containerized-grafana-deploy.git
cd containerized-grafana-deploy
```

### Step 2: Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit configuration with your values
vi .env
```

**Important:** Update these critical values in `.env` **BEFORE running the install script**:

- `INFLUXDB_TOKEN` - **YOU MUST GENERATE THIS MANUALLY:**

  ```bash
  openssl rand -base64 32
  ```

  This token is set during InfluxDB first-time initialization and cannot be auto-generated.
  Copy the output and paste it into your `.env` file.

- `GRAFANA_ADMIN_PASSWORD` - Strong password (16+ chars)
- `INFLUXDB_ADMIN_PASSWORD` - Strong password (16+ chars)
- `ZABBIX_URL` - Your Zabbix API endpoint (e.g., `http://zabbix.example.com/api_jsonrpc.php`)
- `ZABBIX_API_TOKEN` - Generate in Zabbix UI (see Zabbix Integration section below)

**Firewall Configuration (Automatic):**

The install script will automatically configure firewall rules if `CONFIGURE_FIREWALL=true`:

- `CONFIGURE_FIREWALL` - Set to `true` to auto-configure firewall (default: `true`)
- `GRAFANA_ADMIN_SUBNET` - Subnet allowed to access Grafana (e.g., `10.1.10.0/24`)
- `LIBRENMS_VM_IP` - IP address of LibreNMS VM (e.g., `10.2.2.100`)

**Example configuration:**

```bash
# Automatic firewall configuration
CONFIGURE_FIREWALL=true
GRAFANA_ADMIN_SUBNET=10.1.10.0/24
LIBRENMS_VM_IP=10.2.2.100
```

To skip automatic firewall configuration, set `CONFIGURE_FIREWALL=false` and configure manually later.

### Step 3: Run Installation

```bash
# Run as root
sudo ./scripts/install.sh
```

The installation script will:

1. ✅ Check prerequisites
2. ✅ Create directory structure (`/srv/obs/*`)
3. ✅ Copy configuration files
4. ✅ Set permissions and SELinux labels
5. ✅ Install Quadlet unit files
6. ✅ Pull container images
7. ✅ Start all services
8. ✅ Configure firewall rules (if `CONFIGURE_FIREWALL=true`)

### Step 4: Verify Installation

```bash
# Run health check
sudo ./scripts/health-check.sh
```

### Step 5: Access Grafana

Open your browser and navigate to:

**With HTTPS (if `TLS_ENABLED=true`):**

```text
https://grafana.lab:3000
```

**With HTTP (if `TLS_ENABLED=false` or not set):**

```text
http://<your-server-ip>:3000
```

> **Note:** Self-signed certificates will trigger a browser security warning.
> Accept the risk to proceed, or see [HTTPS/TLS Configuration](#-httpstls-configuration)
> for more details.

Login with credentials from `.env`:

- Username: `${GRAFANA_ADMIN_USER}`
- Password: `${GRAFANA_ADMIN_PASSWORD}`

---

## 🔧 Configuration

### Directory Structure

```text
/srv/obs/
├── grafana/
│   ├── data/                 # Grafana database and plugins
│   ├── provisioning/         # Auto-provisioned datasources
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── plugins/
│   │       └── plugins.yaml
│   └── tls/                  # TLS certificates (if enabled)
│       ├── grafana.crt       # Self-signed certificate
│       └── grafana.key       # Private key
├── influxdb/
│   ├── data/                 # InfluxDB time-series data
│   └── config/               # InfluxDB configuration
├── prometheus/
│   ├── data/                 # Prometheus TSDB
│   └── config/
│       └── prometheus.yml    # Scrape configuration
├── loki/
│   ├── data/                 # Loki chunks and indexes
│   └── config/
│       └── loki.yaml         # Loki configuration
└── alloy/
    ├── data/                 # Alloy state
    └── config/
        └── config.alloy      # Log collection config
```

### Quadlet Files

Located in `/etc/containers/systemd/`:

```text
obs-network.network      # Podman bridge network
grafana.container        # Grafana service
influxdb.container       # InfluxDB service
prometheus.container     # Prometheus service
loki.container           # Loki service
alloy.container          # Alloy agent
```

### Systemd Service Management

```bash
# Check status
systemctl status grafana.service
systemctl status prometheus.service
systemctl status loki.service
systemctl status influxdb.service
systemctl status alloy.service

# View logs
journalctl -u grafana.service -f
journalctl -u prometheus.service -n 100

# Restart a service
systemctl restart grafana.service

# Stop/Start all services
systemctl stop grafana alloy loki prometheus influxdb
systemctl start influxdb prometheus loki alloy grafana
```

### 🔒 HTTPS/TLS Configuration

Grafana supports HTTPS using self-signed certificates for secure access.

#### Automatic Certificate Generation

The installation script automatically generates a 10-year self-signed certificate when `TLS_ENABLED=true`.

**Certificate Specifications:**

- **Algorithm:** RSA 4096-bit
- **Hash:** SHA-256
- **Validity:** 3650 days (10 years)
- **Subject Alternative Names (SANs):** Configurable via environment variables

#### Configuration

Edit `.env` to enable HTTPS:

```bash
# Enable HTTPS
TLS_ENABLED=true

# Certificate Common Name (must be grafana.lab)
TLS_CERT_CN=grafana.lab

# Subject Alternative Names (comma-separated)
TLS_CERT_SANS=DNS:grafana.lab,DNS:grafana,DNS:localhost,IP:10.1.10.100

# Certificate storage location
TLS_DIR=/srv/obs/grafana/tls

# Certificate validity (days)
TLS_CERT_VALIDITY_DAYS=3650

# RSA key size
TLS_KEY_SIZE=4096
```

#### Certificate Files

Generated certificates are stored in `${TLS_DIR}` (default: `/srv/obs/grafana/tls/`):

```text
/srv/obs/grafana/tls/
├── grafana.crt    # Certificate (644)
└── grafana.key    # Private key (600)
```

#### Access Grafana with HTTPS

When TLS is enabled, access Grafana at:

```text
https://grafana.lab:3000
```

**Browser Warning:** Self-signed certificates will trigger a browser security warning. You can:

1. **Accept the risk** and proceed (recommended for lab/internal use)
2. **Import the certificate** into your browser's trusted certificate store
3. **Use a proper CA-signed certificate** for production environments

#### Automatic Certificate Management

The installation script (`scripts/install.sh`) includes intelligent certificate management:

**When you run `scripts/install.sh`:**

- ✅ **Certificate exists and valid** → Skips generation, uses existing certificate
- 🔄 **Certificate missing** → Generates new certificate
- 🔄 **Certificate invalid** → Regenerates certificate
- 🔄 **Certificate expires within 30 days** → Regenerates certificate

This means you can safely re-run the installer without regenerating certificates unnecessarily.
The TLS generation step is **idempotent** and will preserve valid certificates.

**Example output when certificate already exists:**

```text
[INFO] TLS is enabled - generating self-signed certificates...
[SUCCESS] Valid certificate already exists
[INFO] Certificate details:
  Subject: C=US, ST=Lab, L=Lab, O=Lab, OU=Observability, CN=grafana.lab
  Valid Until: Jan 26 17:44:55 2036 GMT
  Days Remaining: 3650
[INFO] No action needed - certificate is valid and not near expiry
```

#### Manual Certificate Generation

To regenerate certificates manually (outside of the install script):

```bash
sudo bash -c 'set -a; source .env; set +a; scripts/generate-selfsigned-tls.sh'
```

Or if you need to force regeneration, delete the existing certificate first:

```bash
sudo rm -f /srv/obs/grafana/tls/grafana.{crt,key}
sudo bash -c 'set -a; source .env; set +a; scripts/generate-selfsigned-tls.sh'
```

#### Disable HTTPS

To use HTTP instead:

```bash
# In .env file
TLS_ENABLED=false
```

Then re-run the installation:

```bash
sudo scripts/install.sh
```

Grafana will be accessible at `http://grafana.lab:3000` or `http://<your-ip>:3000`.

#### Certificate Expiry Monitoring

To check certificate expiry:

```bash
openssl x509 -in /srv/obs/grafana/tls/grafana.crt -noout -enddate
```

For automated monitoring, add a cron job or use Grafana's built-in certificate monitoring dashboards.

---

## 🔐 Environment Variables

All configuration is managed through environment variables defined in the `.env` file.
This section provides a comprehensive reference of all variables used by the deployment.

### Required Variables

These variables **must** be set in `.env` before running the installation:

| Variable | Used By | Purpose | Notes |
|----------|---------|---------|-------|
| `INFLUXDB_ADMIN_USER` | InfluxDB | Initial admin username | Set during first-time setup |
| `INFLUXDB_ADMIN_PASSWORD` | InfluxDB | Initial admin password | Minimum 16 characters recommended |
| `INFLUXDB_ORG` | InfluxDB, Grafana | Organization name | Default: `observability` |
| `INFLUXDB_BUCKET` | InfluxDB, Grafana | Bucket name for LibreNMS data | Default: `librenms` |
| `INFLUXDB_TOKEN` | InfluxDB, Grafana | Admin API token | **Generate manually:** `openssl rand -base64 32` |
| `GRAFANA_ADMIN_USER` | Grafana | Admin username | Default: `admin` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana | Admin password | Change from default immediately |
| `GRAFANA_DOMAIN` | Grafana | Server domain or IP | Used for `root_url` configuration |

### Zabbix Integration Variables

These variables configure the Zabbix integration via the `alexanderzobnin-zabbix-app` plugin:

| Variable | Required | Used By | Purpose | Notes |
|----------|----------|---------|---------|-------|
| `GRAFANA_INSTALL_ZABBIX_PLUGIN` | Yes | install.sh, Grafana | Enable Zabbix plugin | Set to `true` or `false` |
| `GRAFANA_ZABBIX_PLUGIN_ID` | Conditional | install.sh, Grafana | Plugin identifier | `alexanderzobnin-zabbix-app` |
| `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` | Conditional | Grafana | Trends threshold (days) | Recommended: `7` |
| `ZABBIX_URL` | Conditional | Grafana datasource | Zabbix API endpoint | `http://host/api_jsonrpc.php` |
| `ZABBIX_API_TOKEN` | Conditional | Grafana datasource | API auth token | Generate in Zabbix UI |

**Conditional:** Required only if `GRAFANA_INSTALL_ZABBIX_PLUGIN=true`

> **Important:** Username/password authentication is **not supported**. Zabbix integration
> requires API token authentication only. See [Zabbix Integration](#-zabbix-integration)
> for token generation instructions.

### Firewall Configuration Variables

These variables control automatic firewall configuration during installation:

| Variable | Required | Used By | Purpose | Notes |
|----------|----------|---------|---------|-------|
| `CONFIGURE_FIREWALL` | No | install.sh, uninstall.sh | Enable firewall automation | Skip if not set |
| `GRAFANA_ADMIN_SUBNET` | Conditional | install.sh | Grafana access subnet | CIDR: `10.1.10.0/24` |
| `LIBRENMS_VM_IP` | Conditional | install.sh | InfluxDB access IP | Single IP: `10.2.2.100` |

**Conditional:** Required only if `CONFIGURE_FIREWALL=true`

### TLS/HTTPS Configuration Variables

These variables control HTTPS/TLS certificate generation and configuration for Grafana:

| Variable | Required | Used By | Purpose | Notes |
|----------|----------|---------|---------|-------|
| `TLS_ENABLED` | No | install.sh, Grafana | Enable HTTPS | Set to `true` or `false` (default: `false`) |
| `TLS_DIR` | Conditional | install.sh, Grafana | Certificate storage directory | Default: `/srv/obs/grafana/tls` |
| `TLS_CERT_CN` | Conditional | TLS script | Certificate Common Name | **Must be:** `grafana.lab` |
| `TLS_CERT_SANS` | Conditional | TLS script | Subject Alternative Names | Comma-separated DNS/IP list |
| `TLS_CERT_VALIDITY_DAYS` | Conditional | TLS script | Certificate validity period | Default: `3650` (10 years) |
| `TLS_KEY_SIZE` | Conditional | TLS script | RSA key size in bits | Default: `4096` |

**Conditional:** Required only if `TLS_ENABLED=true`

> **Important:** The Common Name (`TLS_CERT_CN`) must be set to `grafana.lab` as per requirements.
> Include this in your `TLS_CERT_SANS` along with any additional DNS names or IP addresses.

### Optional Variables (Future Extensions)

These variables are **not currently consumed** by the deployment but exist for potential
future extensions or as reference values:

| Variable | Purpose | Current Status |
|----------|---------|----------------|
| `INFLUXDB_URL` | External InfluxDB URL | Documentation only - configure on LibreNMS side |
| `INFLUXDB_PORT` | InfluxDB port | Documentation only - hardcoded to `8086` |
| `ZABBIX_DB_HOST` | Zabbix MySQL hostname | Reserved for optional direct DB access (commented out) |
| `ZABBIX_DB_NAME` | Zabbix database name | Reserved for optional direct DB access (commented out) |
| `ZABBIX_DB_USER` | Zabbix database user | Reserved for optional direct DB access (commented out) |
| `ZABBIX_DB_PASSWORD` | Zabbix database password | Reserved for optional direct DB access (commented out) |

> **Note:** The Zabbix database variables reference an optional datasource configuration
> that is **commented out** in `datasources.yaml`. The deployment uses API-only access by
> default. Direct database access can be enabled by uncommenting the `Zabbix-DB` datasource.

### Variable Usage Matrix

This table shows which components consume each variable:

| Variable | Quadlets | Configs | Scripts | Runtime |
|----------|----------|---------|---------|---------|
| `INFLUXDB_*` (admin/org/bucket/token) | ✅ | ✅ | ✅ | ✅ |
| `GRAFANA_ADMIN_*` | ✅ | ❌ | ✅ | ✅ |
| `GRAFANA_DOMAIN` | ✅ | ❌ | ❌ | ✅ |
| `GRAFANA_INSTALL_ZABBIX_PLUGIN` | ✅ | ❌ | ✅ | ✅ |
| `GRAFANA_ZABBIX_PLUGIN_ID` | ✅ | ❌ | ✅ | ✅ |
| `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` | ✅ | ✅ | ❌ | ✅ |
| `ZABBIX_URL` | ✅ | ✅ | ✅ | ✅ |
| `ZABBIX_API_TOKEN` | ✅ | ✅ | ✅ | ✅ |
| `TLS_ENABLED` | ✅ | ❌ | ✅ | ✅ |
| `TLS_DIR` | ✅ | ❌ | ✅ | ❌ |
| `TLS_CERT_CN` | ❌ | ❌ | ✅ | ❌ |
| `TLS_CERT_SANS` | ❌ | ❌ | ✅ | ❌ |
| `TLS_CERT_VALIDITY_DAYS` | ❌ | ❌ | ✅ | ❌ |
| `TLS_KEY_SIZE` | ❌ | ❌ | ✅ | ❌ |
| `CONFIGURE_FIREWALL` | ❌ | ❌ | ✅ | ❌ |
| `GRAFANA_ADMIN_SUBNET` | ❌ | ❌ | ✅ | ❌ |
| `LIBRENMS_VM_IP` | ❌ | ❌ | ✅ | ❌ |

**Legend:**
- ✅ = Used by this component
- ❌ = Not used by this component

### Environment Variable Sources

```text
┌─────────────────┐
│  .env.example   │  ← Template with defaults and documentation
└────────┬────────┘
         │ User copies and customizes
         ↓
┌─────────────────┐
│      .env       │  ← SINGLE SOURCE OF TRUTH (not in git)
└────────┬────────┘
         │
         ├──→ scripts/install.sh    (validates required vars)
         │
         ├──→ quadlets/*.container  (envsubst replaces ${VAR})
         │
         └──→ Grafana provisioning  (${VAR} interpolation)
```

### Environment Variable Security

1. **Never commit `.env` to version control** - it's in `.gitignore` for security

2. **Generate strong tokens and passwords:**

   ```bash
   openssl rand -base64 32  # For INFLUXDB_TOKEN
   openssl rand -base64 24  # For passwords
   ```

3. **Set restrictive permissions:**

   ```bash
   chmod 600 .env
   ```

4. **Rotate credentials regularly** - especially API tokens

5. **Use API tokens, not passwords** - for Zabbix integration

6. **Validate `.env` before deployment:**

   ```bash
   diff .env .env.example  # Check for missing variables
   ```

---

## 🔌 Integration Setup

### 📊 Zabbix Integration

The Zabbix datasource is auto-provisioned using API token authentication.

**Configure in `.env`:**

```bash
ZABBIX_URL=http://zabbix.example.com/api_jsonrpc.php
ZABBIX_API_TOKEN=<your-api-token>  # Generate in Zabbix UI
```

**Generate Zabbix API Token:**

1. Login to Zabbix web interface as admin
2. Navigate to: **Administration → Users**
3. Select the user for Grafana integration (or create new user with read permissions)
4. Go to **"API tokens"** tab
5. Click **"Create API token"**
6. Set description: `Grafana Integration`
7. Set expiration: Leave empty for no expiration (or set as needed)
8. Click **"Add"** and copy the generated token
9. Paste token into `.env` as `ZABBIX_API_TOKEN` value

**Important Notes:**

- ✅ API token authentication is **required** (username/password not supported)
- ✅ User must have read permissions to required host groups
- ✅ Token never expires if expiration is not set
- ✅ Trends threshold set to 7 days for optimal performance

**Plugin:** `alexanderzobnin-zabbix-app` (auto-installed)

### 📡 LibreNMS Integration

LibreNMS pushes metrics to InfluxDB on this VM.

**Configure in `.env`:**

```bash
INFLUXDB_URL=http://grafana.example.com:8086  # Change to your VM hostname/IP
INFLUXDB_PORT=8086
INFLUXDB_ORG=observability
INFLUXDB_BUCKET=librenms
INFLUXDB_TOKEN=<generated-token>
```

**Configure LibreNMS:**

1. Navigate to LibreNMS Settings → Plugins → InfluxDB
2. Enable InfluxDB export
3. Configure:

   ```text
   URL: http://<your-grafana-vm-ip>:8086  # Use INFLUXDB_URL value
   Organization: observability             # Use INFLUXDB_ORG value
   Bucket: librenms                        # Use INFLUXDB_BUCKET value
   Token: <INFLUXDB_TOKEN from .env>       # Copy from .env
   ```

4. Test connection and save

**Verify Connectivity:**

```bash
# From LibreNMS VM
curl http://<grafana-vm-ip>:8086/health

# Expected: {"status":"pass","message":"ready for queries and writes"}
```

**Grafana Datasource:** Auto-provisioned as `InfluxDB-LibreNMS`

### 📈 Prometheus Integration

Prometheus scrapes metrics from exporters.

**Add Targets:**

Edit `/srv/obs/prometheus/config/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['host.containers.internal:9100']
        labels:
          instance: 'grafana-vm'
```

Reload configuration:

```bash
systemctl restart prometheus.service
```

### 📝 Loki Integration

Alloy collects systemd journal logs automatically.

**View logs in Grafana:**

1. Navigate to Explore
2. Select "Loki" datasource
3. Query example: `{unit="grafana.service"}`

---

## ✅ Health Check

Run the comprehensive health check script:

```bash
sudo ./scripts/health-check.sh
```

**Checks performed:**

- ✅ Systemd service status (all 6 services)
- ✅ Container running state
- ✅ Podman network connectivity
- ✅ Bind mount directories and permissions
- ✅ HTTP health endpoints (internal and external)
- ✅ Disk usage warnings
- ✅ Container resource usage
- ✅ Configuration file presence
- ✅ Port listening status
- ✅ SELinux labels
- ✅ Quadlet file presence
- ✅ Firewall rules
- ✅ Grafana datasources
- ✅ InfluxDB initialization
- ✅ Grafana plugins
- ✅ Service log errors

**Example output:**

```text
╔════════════════════════════════════════════════════════════╗
║       Observability Stack Health Check Report             ║
╚════════════════════════════════════════════════════════════╝

[INFO] Checking systemd services...
[✓] Service obs-network-network is running
[✓] Service influxdb is running
[✓] Service prometheus is running
[✓] Service loki is running
[✓] Service alloy is running
[✓] Service grafana is running

[INFO] Checking HTTP endpoints...
[✓] Grafana endpoint is healthy (HTTP 200)
[✓] Prometheus endpoint is healthy
[✓] Loki endpoint is healthy
[✓] InfluxDB endpoint is healthy

...

Overall Status: HEALTHY (59/60 checks passed)
```

---

## 🗑️ Uninstallation

The uninstall script supports multiple modes for safe and flexible removal.

### 🔍 Preview Mode (Dry-Run)

Preview what will be removed without making any changes:

```bash
sudo ./scripts/uninstall.sh --dry-run
```

Safe to run anytime. No confirmation required.

### 🛡️ Clean Removal (Preserve Data - Default)

```bash
sudo ./scripts/uninstall.sh
# or explicitly:
sudo ./scripts/uninstall.sh --preserve-data
```

This will:
- Stop and remove all containers
- Remove Quadlet configuration files
- Remove Podman network
- **Remove firewall rules** for ports 3000, 8086, and 9090 (if configured)
- **Preserve data in `/srv/obs`** (Grafana dashboards, metrics, logs)

### 🗑️ Complete Removal (Delete All Data)

```bash
sudo ./scripts/uninstall.sh --remove-data
```

⚠️ **Warning:** This permanently deletes all monitoring data, logs, and
configurations.

Removes everything above plus:
- All data in `/srv/obs/`
- SELinux file contexts

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-d` | Preview changes without executing |
| `--preserve-data` | `-p` | Keep data (default behavior) |
| `--remove-data` | `-r` | Permanently delete all data |
| `--help` | `-h` | Show usage information |

### Examples

```bash
# Preview full uninstall with data removal
sudo ./scripts/uninstall.sh --dry-run --remove-data

# Quick reinstall (keep existing data)
sudo ./scripts/uninstall.sh && sudo ./scripts/install.sh

# Complete fresh start
sudo ./scripts/uninstall.sh --remove-data && sudo ./scripts/install.sh
```

---

## 🔍 Troubleshooting

### Common Issues

#### 🔴 Service won't start

```bash
# Check service status
systemctl status grafana.service

# View full logs
journalctl -u grafana.service -n 100

# Check container logs
podman logs grafana
```

#### 🔴 Permission denied errors

```bash
# Verify SELinux labels
ls -lZ /srv/obs/

# Re-apply SELinux labels
sudo restorecon -Rv /srv/obs/
```

#### 🔴 Cannot install dashboard or plugin from grafana.com

**Symptoms:**
- Import fails when entering a Dashboard ID
- Plugin installation hangs or fails
- "Too many open files" or process limit errors in logs

**Solutions:**

1. **Increase Grafana PID limit** (default 2048 may be insufficient):

   Edit `quadlets/grafana.container` and add under Resource limits:

   ```ini
   PidsLimit=4096
   ```

   Then re-run install or manually update `/etc/containers/systemd/grafana.container` and restart:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart grafana.service
   ```

2. **Verify connectivity from container:**

   ```bash
   podman exec -it grafana curl -I https://grafana.com
   ```

   Expected: `HTTP/2 200`

3. **Check Grafana logs for errors:**

   ```bash
   journalctl -u grafana.service -n 100 --no-pager | grep -i "error\|fail"
   ```

#### 🔴 Port already in use

```bash
# Check what's using port 3000
sudo ss -tulpn | grep 3000

# Stop conflicting service
sudo systemctl stop <conflicting-service>
```

#### 🔴 Cannot connect to Podman network

```bash
# Verify network exists
podman network ls

# Inspect network
podman network inspect obs-net

# Recreate network
podman network rm obs-net
systemctl restart obs-network-network.service
```

#### 🔴 LibreNMS cannot push metrics to InfluxDB

**Symptoms:**
- No LibreNMS data in Grafana
- InfluxDB health check fails from LibreNMS VM
- Connection timeouts from LibreNMS

**Solutions:**

1. **Verify InfluxDB is running and healthy:**

   ```bash
   # On Grafana VM
   systemctl status influxdb.service
   curl http://localhost:8086/health
   # Expected: {"status":"pass","message":"ready for queries and writes"}
   ```

2. **Test connectivity from LibreNMS VM:**

   ```bash
   # From LibreNMS VM (replace with your Grafana VM IP)
   curl http://<grafana-vm-ip>:8086/health

   # If timeout or connection refused, check firewall
   ```

3. **Check firewall allows port 8086:**

   ```bash
   # On Grafana VM
   sudo firewall-cmd --list-ports

   # Add rule if missing (LibreNMS VM IP: x.x.x.x)
   sudo firewall-cmd --permanent \
     --add-rich-rule='rule family="ipv4" source address="x.x.x.x/32" \
     port port="8086" protocol="tcp" accept'
   sudo firewall-cmd --reload
   ```

4. **Verify InfluxDB configuration in LibreNMS:**

   - URL must be: `http://<grafana-vm-ip>:8086`
   - Organization: Value from `INFLUXDB_ORG` in `.env`
   - Bucket: Value from `INFLUXDB_BUCKET` in `.env`
   - Token: Value from `INFLUXDB_TOKEN` in `.env`

5. **Check InfluxDB logs for errors:**

   ```bash
   journalctl -u influxdb.service -f
   ```

6. **Test write access with curl:**

   ```bash
   # From LibreNMS VM (replace values)
   INFLUXDB_URL="http://<grafana-vm-ip>:8086"
   WRITE_URL="${INFLUXDB_URL}/api/v2/write?org=observability&bucket=librenms"
   curl -X POST "${WRITE_URL}" \
     -H "Authorization: Token <your-influxdb-token>" \
     -H "Content-Type: text/plain" \
     --data-raw "test_metric value=1"

   # If successful, you should see HTTP 204
   ```

### Log Locations

| Component | Log Command |
|-----------|-------------|
| Grafana | `journalctl -u grafana.service -f` |
| Prometheus | `journalctl -u prometheus.service -f` |
| Loki | `journalctl -u loki.service -f` |
| InfluxDB | `journalctl -u influxdb.service -f` |
| Alloy | `journalctl -u alloy.service -f` |

### Debug Commands

```bash
# List all containers
podman ps -a

# Inspect container
podman inspect grafana

# Check resource usage
podman stats

# Test HTTP endpoints
curl http://localhost:3000/api/health
curl http://localhost:9090/-/healthy
curl http://localhost:3100/ready
curl http://localhost:8086/health
```

---

## 📊 Tuning and Scaling

See [docs/TUNING.md](docs/TUNING.md) for detailed tuning and scaling guidance.

### Quick Reference

#### Retention Configuration

**Prometheus** (in Quadlet file):

```text
--storage.tsdb.retention.time=365d
--storage.tsdb.retention.size=200GB
```

**Loki** (in `loki.yaml`):

```yaml
limits_config:
  retention_period: 8760h  # 365 days
```

**InfluxDB** (in environment):

```bash
DOCKER_INFLUXDB_INIT_RETENTION=8760h
```

#### Resource Limits

Edit Quadlet files in `/etc/containers/systemd/*.container`:

```ini
[Container]
Memory=8G
MemorySwap=8G
CPUQuota=400%  # 4 CPU cores
PidsLimit=4096  # Grafana: required for dashboard/plugin installs from grafana.com
```

Reload after changes:

```bash
systemctl daemon-reload
systemctl restart <service>.service
```

#### Disk Space Management

```bash
# Check usage
df -h /srv/obs

# Prometheus - Clean old data manually if needed
podman exec prometheus promtool tsdb clean --timestamp=<unix-timestamp> /prometheus

# Loki - Compaction happens automatically
# Check compactor logs
journalctl -u loki.service | grep compactor
```

---

## 🔒 Security

### Security Best Practices

- ✅ **SELinux enforcing** mode enabled
- ✅ **No secrets in git** - `.env` is gitignored
- ✅ **Strong passwords** - Minimum 16 characters
- ✅ **Token rotation** - Regularly rotate InfluxDB tokens
- ✅ **Least privilege** - Containers run as non-root where possible
- ✅ **Firewall** - Ports 3000 and 8086 restricted to trusted sources

### Credential Management

#### Stored in `.env` (never committed to git)

- Grafana admin credentials
- InfluxDB admin credentials and token
- Zabbix API credentials
- Optional database credentials

**File permissions:**

```bash
chmod 600 .env
chown root:root .env
```

### Network Security

**Externally Exposed Ports:**

- `3000/tcp` - Grafana UI (restricted via firewall to `GRAFANA_ADMIN_SUBNET`)
- `8086/tcp` - InfluxDB API (restricted via firewall to `LIBRENMS_VM_IP/32`)
- `9090/tcp` - Prometheus UI/API (optional, restricted via firewall to `PROMETHEUS_ADMIN_SUBNET`)

**Internal-only Ports:**

- `3100/tcp` - Loki (bind to container network only)

**Firewall Example:**

```bash
# Allow Grafana from admin subnet
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source address="${GRAFANA_ADMIN_SUBNET}" \
  port port="3000" protocol="tcp" accept'

# Allow InfluxDB from LibreNMS VM only
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source address="${LIBRENMS_VM_IP}/32" \
  port port="8086" protocol="tcp" accept'

# Allow Prometheus from monitoring subnet (optional)
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" \
  source address="${PROMETHEUS_ADMIN_SUBNET}" \
  port port="9090" protocol="tcp" accept'

firewall-cmd --reload
```

### SELinux Contexts

All bind mounts use `container_file_t`:

```bash
semanage fcontext -a -t container_file_t "/srv/obs(/.*)?"
restorecon -Rv /srv/obs
```

---

## 📚 Documentation

### Additional Documentation

- [docs/TUNING.md](docs/TUNING.md) - Performance tuning and scaling
- [docs/requirements.md](template/docs/requirements.md) - Complete requirements specification
- [docs/ai/CONTEXT.md](template/docs/ai/CONTEXT.md) - AI engineering standards

### External References

- [Podman Documentation](https://docs.podman.io/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [InfluxDB Documentation](https://docs.influxdata.com/influxdb/v2/)

---

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

```text
Copyright 2026 Your Organization

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

## 🤝 Contributing

Contributions are welcome! Please ensure:

- All scripts follow bash standards (see `template/docs/ai/CONTEXT.md`)
- Run pre-commit hooks: `./scripts/run-precommit.sh`
- No secrets in commits
- Update documentation for new features

---

## 💬 Support

For issues, questions, or contributions:

- Open an issue on GitHub
- Review existing documentation
- Check troubleshooting section above

---

## Built with ❤️ for RHEL 10 and Podman
