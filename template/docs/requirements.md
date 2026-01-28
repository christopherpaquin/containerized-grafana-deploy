You are Cursor acting as an Expert Infrastructure-as-Code (IaC) and Linux Observability Engineer.

PRIMARY RULES (READ FIRST)
- Do NOT generate code until you have fully reviewed and summarized all requirements below.
- Target OS: RHEL 10
- Runtime: Podman using crun and netavark
- Orchestration: Podman Quadlets ONLY (systemd-managed)
- No docker-compose
- No manual podman run commands
- Container base images must be:
  - CentOS Stream 9 or
  - Red Hat UBI
- Alpine images are NOT allowed.
- All deployments must be idempotent.
- All components must be deployable and removable via script.

---

## ENVIRONMENT OVERVIEW

### Virtual Machines
1. **LibreNMS VM**
   - Already deployed
   - Containerized
   - Uses MariaDB
   - Will export metrics to InfluxDB

2. **Zabbix VM**
   - Already deployed
   - Zabbix 7.x
   - API available
   - Database may be queried directly if needed

3. **Grafana VM (this project)**
   - New deployment
   - Hosts:
     - Grafana
     - Loki
     - Prometheus
     - Grafana Alloy
     - InfluxDB 2.x
   - All deployed as containers
   - All managed via Podman Quadlets

---

## OBJECTIVE

Deploy a production-grade observability stack on the **Grafana VM** that:

- Visualizes metrics from:
  - LibreNMS (via InfluxDB)
  - Zabbix (via API + optional DB access)
- Collects logs via Loki + Alloy
- Supports Prometheus-style metrics
- Uses bind mounts for all persistent data
- Is fully reproducible and idempotent
- Is safe to uninstall cleanly

---

## PLATFORM & SCALE

- OS: RHEL 10
- Runtime: Podman + systemd
- Network backend: netavark
- Scale:
  - ~200 monitored devices
  - 1 year retention
- Resources:
  - 8 vCPU
  - 24 GB RAM
  - 500 GB SSD

---

## COMPONENTS TO DEPLOY (Grafana VM)

### Required Containers
- Grafana
- Loki
- Prometheus
- Grafana Alloy
- InfluxDB 2.x

All must:
- Use bind mounts
- Run in a dedicated Podman network
- Be managed via Quadlets
- Start automatically via systemd

---

## NETWORKING & PORTS

### Exposed
- Grafana → `3000/tcp`

### Internal-only
- Prometheus → `9090`
- Loki → `3100`
- InfluxDB → `8086`
- Alloy → no external port

### Remote Access Requirements
Grafana VM must be able to reach:
- LibreNMS MariaDB (TCP 3306)
- Zabbix API (TCP 80/443)

Firewall rules must restrict access to Grafana VM only.

---

## BIND MOUNT LAYOUT (MANDATORY)

/srv/obs/grafana/data -> /var/lib/grafana
/srv/obs/prometheus/data -> /prometheus
/srv/obs/prometheus/config -> /etc/prometheus
/srv/obs/loki/data -> /loki
/srv/obs/loki/config -> /etc/loki
/srv/obs/alloy/data -> /var/lib/alloy
/srv/obs/alloy/config -> /etc/alloy
/srv/obs/influxdb/data -> /var/lib/influxdb2
/srv/obs/influxdb/config -> /etc/influxdb2


SELinux labeling must be handled correctly.

---

## INTEGRATION REQUIREMENTS

### LibreNMS → InfluxDB
- LibreNMS exports SNMP metrics to InfluxDB 2.x
- InfluxDB runs on the Grafana VM
- Grafana queries InfluxDB for LibreNMS data
- LibreNMS is NOT queried directly by Grafana

### Zabbix → Grafana
- Install Grafana plugin:
  - `alexanderzobnin-zabbix-app`
- Configure:
  - Zabbix API datasource
  - Optional direct DB datasource (if required)
- Set trends threshold to 7 days

### Prometheus
- Used for exporter-based metrics
- Not a replacement for LibreNMS or Zabbix

### Loki + Alloy
- Alloy collects logs
- Loki stores logs
- Grafana visualizes logs

---

## REQUIRED DELIVERABLES

### 1. Idempotent Install Script
Must:
- Create directories
- Create Podman network
- Write Quadlet files
- Apply SELinux labels
- Reload systemd
- Enable & start services
- Be safe to run multiple times

### 2. Uninstall Script
Must:
- Stop/disable all services
- Remove Quadlets
- Remove created directories
- Remove Podman network
- Leave LibreNMS and Zabbix untouched

### 3. Health Check Script
Must verify:
- Containers running
- systemd units active
- Bind mounts exist and writable
- HTTP health endpoints:
  - Grafana
  - Loki
  - Prometheus
  - InfluxDB
- Connectivity to:
  - LibreNMS DB
  - Zabbix API

### 4. Configuration Artifacts
Provide:
- Quadlet files
- Prometheus config
- Loki config
- Alloy config
- Grafana provisioning files
- InfluxDB initialization config

---

## CONSTRAINTS

- Do NOT use Docker or docker-compose
- Do NOT use Alpine images
- Do NOT include Bacula or backups
- Do NOT invent unsupported LibreNMS or Zabbix features
- Avoid redundant explanation
- Prefer correctness over brevity

---

## REQUIRED RESPONSE FORMAT

1. Summary of understanding
2. Architecture overview
3. Network & data flow diagram (text)
4. Directory layout
5. Quadlet definitions
6. Install script
7. Uninstall script
8. Health check script
9. Tuning and scaling notes

---

BEGIN NOW.

First summarize the requirements and identify any assumptions or conflicts before generating code
