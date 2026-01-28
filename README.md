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
| **Prometheus** | Metrics collection & storage | 9090 | ❌ Internal |
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
- [ ] Firewall configured (port 3000 open for Grafana)
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

**Important:** Update these critical values in `.env`:

- `INFLUXDB_TOKEN` - Generate with: `openssl rand -base64 32`
- `GRAFANA_ADMIN_PASSWORD` - Strong password (16+ chars)
- `INFLUXDB_ADMIN_PASSWORD` - Strong password (16+ chars)
- `ZABBIX_URL` - Your Zabbix API endpoint
- `ZABBIX_USER` and `ZABBIX_PASSWORD` - Zabbix credentials

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

### Step 4: Verify Installation

```bash
# Run health check
sudo ./scripts/health-check.sh
```

### Step 5: Access Grafana

Open your browser and navigate to:

```text
http://<your-server-ip>:3000
```

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
│   └── provisioning/         # Auto-provisioned datasources
│       ├── datasources/
│       │   └── datasources.yaml
│       └── plugins/
│           └── plugins.yaml
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

- ✅ Systemd service status
- ✅ Container running state
- ✅ Podman network connectivity
- ✅ Bind mount directories
- ✅ HTTP health endpoints
- ✅ Disk usage warnings
- ✅ Container resource usage

**Example output:**

```text
╔════════════════════════════════════════════════════════════╗
║       Observability Stack Health Check Report             ║
╚════════════════════════════════════════════════════════════╝

[INFO] Checking systemd services...
[✓] Service obs-network is running
[✓] Service influxdb is running
[✓] Service prometheus is running
[✓] Service loki is running
[✓] Service alloy is running
[✓] Service grafana is running

...

Overall Status: HEALTHY
```

---

## 🗑️ Uninstallation

### Clean Removal (Preserve Data)

```bash
sudo ./scripts/uninstall.sh
```

This removes services and containers but **preserves data** in `/srv/obs`.

### Complete Removal (Delete Data)

```bash
sudo ./scripts/uninstall.sh --remove-data
```

⚠️ **Warning:** This permanently deletes all monitoring data, logs, and configurations.

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
systemctl restart obs-network.service
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
- ✅ **Firewall** - Only port 3000 exposed externally

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

**Exposed Ports:**

- `3000/tcp` - Grafana UI (restrict via firewall)

**Internal-only Ports:**

- `8086/tcp` - InfluxDB (bind to container network only)
- `9090/tcp` - Prometheus (bind to container network only)
- `3100/tcp` - Loki (bind to container network only)

**Firewall Example:**

```bash
# Allow Grafana only from trusted networks
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" \
  port port="3000" protocol="tcp" accept'
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
