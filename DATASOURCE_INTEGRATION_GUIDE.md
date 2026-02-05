# Post-Deployment: Datasource Integration Guide

**Complete guide for connecting Zabbix and LibreNMS to your Grafana observability stack.**

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Zabbix Integration](#zabbix-integration)
4. [LibreNMS Integration](#librenms-integration)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [Recommended Dashboards](#recommended-dashboards)

---

## Architecture Overview

### Zabbix Architecture

```
┌─────────────┐         ┌─────────────┐
│   Zabbix    │◄─API────│   Grafana   │
│   Server    │  Query  │  (Plugin)   │
└─────────────┘         └─────────────┘
```

- **Method:** Grafana queries Zabbix Web API directly
- **Plugin:** `alexanderzobnin-zabbix-app` (auto-installed)
- **Auth:** API token (username/password NOT supported)
- **Datasource:** Auto-provisioned as `Zabbix`

### LibreNMS Architecture (Direct MySQL Query)

```
┌─────────────┐         ┌─────────────┐
│  LibreNMS   │◄─SQL────│   Grafana   │
│  (MySQL DB) │  Query  │             │
└─────────────┘         └─────────────┘
```

- **Method:** Grafana queries LibreNMS MySQL/MariaDB database directly
- **Database:** `librenms` (MariaDB/MySQL)
- **Query Language:** SQL
- **Datasource:** Configured as `LibreNMS-MySQL`
- **NO Plugin Required:** Uses native MySQL datasource
- **NO Middleware:** Direct access to LibreNMS stored metrics

---

## Prerequisites

### Grafana Stack Requirements
- ✅ Observability stack deployed and healthy
- ✅ Grafana accessible via HTTPS (port 3000)
- ✅ InfluxDB accessible (port 8086)
- ✅ Firewall rules configured during deployment

### External System Requirements

#### Zabbix
- Zabbix Server 5.0+ running and accessible
- Admin access to generate API tokens
- Network connectivity from Grafana to Zabbix

#### LibreNMS
- LibreNMS running (containerized or bare-metal)
- MySQL/MariaDB database accessible (port 3306)
- Network connectivity from Grafana to LibreNMS database (port 3306)
- Database credentials (username/password)

---

## Zabbix Integration

### Step 1: Verify Zabbix Plugin is Installed

The Zabbix plugin is automatically installed during deployment if `GRAFANA_INSTALL_ZABBIX_PLUGIN=true` in `.env`.

**Verify installation:**

```bash
sudo podman exec grafana grafana cli plugins ls | grep zabbix
```

**Expected output:**
```
alexanderzobnin-zabbix-app @ 6.1.2
```

### Step 2: Generate Zabbix API Token

**⚠️ Important:** The Zabbix datasource uses **API token authentication only**. Username/password is NOT supported.

1. Login to Zabbix web interface as administrator

2. Navigate to **Administration → Users**

3. Select the user for Grafana integration (or create a dedicated user)

4. Go to **API tokens** tab

5. Click **Create API token**
   - **Description:** `Grafana Integration`
   - **Expires at:** (optional - leave empty for no expiration)
   - **Enabled:** ✅ Checked

6. Click **Add**

7. **Copy the generated token immediately** (it won't be shown again)

8. Update your `.env` file on the Grafana server:

```bash
ZABBIX_URL=http://zabbix.lab/api_jsonrpc.php
ZABBIX_API_TOKEN=<paste-your-token-here>
```

**Note:** If Zabbix is NOT in a subdirectory, ensure the URL points directly to `api_jsonrpc.php`:
- ✅ `http://zabbix.lab/api_jsonrpc.php`
- ❌ `http://zabbix.lab/zabbix/api_jsonrpc.php` (only if in subdirectory)

### Step 3: Apply Configuration

If you added the Zabbix configuration after initial deployment:

```bash
cd /root/containerized-grafana-deploy
sudo bash scripts/install.sh
```

This will update the Zabbix datasource with your new credentials.

### Step 4: Verify Zabbix Datasource

1. Login to Grafana: `https://grafana.lab:3000`
   - Username: `admin`
   - Password: (from `.env` - `GRAFANA_ADMIN_PASSWORD`)

2. Navigate to **☰ Menu → Connections → Data sources**

3. Click on **Zabbix** datasource

4. Scroll to bottom and click **Save & Test**

**Expected result:**
```
✅ Zabbix API version X.X.X found
```

**If test fails**, see [Troubleshooting: Zabbix](#zabbix-connection-issues) below.

---

## LibreNMS Integration

### Architecture Reminder

Grafana connects **directly to LibreNMS MySQL database**:
1. **LibreNMS** polls network devices (SNMP, etc.) and stores data in MySQL/MariaDB
2. **Grafana** queries the **LibreNMS database** directly using SQL
3. All historical metrics are available immediately (no middleware required)

**No LibreNMS plugin required** - uses native MySQL datasource.

### Step 1: Expose LibreNMS Database Port

The LibreNMS MySQL/MariaDB database must be accessible from your Grafana server.

**If using containerized LibreNMS**, verify port 3306 is exposed:

```bash
# On LibreNMS server
podman ps | grep librenms-db
# OR
docker ps | grep librenms-db
```

**Expected output:**
```
0.0.0.0:3306->3306/tcp    librenms-db
```

**If port is NOT exposed**, add port mapping to your container configuration:

```bash
# For Quadlet/systemd (edit /etc/containers/systemd/librenms-db.container):
PublishPort=3306:3306

# For Docker Compose (edit docker-compose.yml):
ports:
  - "3306:3306"

# Then restart
systemctl restart librenms-db   # For Quadlet
docker-compose restart db       # For Docker Compose
```

### Step 2: Get LibreNMS Database Credentials

**Method 1: From LibreNMS Container Environment**

```bash
# On LibreNMS server
podman exec librenms env | grep -E '(DB_|MYSQL_)'
# OR
docker exec librenms env | grep -E '(DB_|MYSQL_)'
```

**Method 2: From docker-compose.yml or Quadlet file**

```bash
# Look for MYSQL_USER and MYSQL_PASSWORD
cat docker-compose.yml | grep -A 5 MYSQL
# OR
cat /etc/containers/systemd/librenms-db.container | grep Environment
```

**You'll need:**
- **Host:** LibreNMS server IP (e.g., `10.1.10.58`)
- **Port:** `3306`
- **Database:** `librenms`
- **User:** `librenms` (or as configured)
- **Password:** (from environment variables)

### Step 3: Test Database Connectivity

From your **Grafana server**, test the connection:

```bash
# Test port connectivity
timeout 2 bash -c "echo > /dev/tcp/<librenms-ip>/3306" && echo "✅ Port reachable" || echo "❌ Port not reachable"

# If you have mysql client installed
mysql -h <librenms-ip> -u librenms -p<password> librenms -e "SELECT COUNT(*) FROM devices;"
```

**Expected:** Should return device count

### Step 4: Add MySQL Datasource to Grafana

#### Option A: Automated Script (Recommended) 🚀

Run the integration script from your **Grafana server**:

```bash
cd /root/containerized-grafana-deploy
source .env
sudo ./scripts/integrate-librenms-mysql.sh <librenms-ip> [ssh-user]
```

**Example:**
```bash
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
```

**What the script does:**
1. ✅ Tests SSH connectivity to LibreNMS server
2. ✅ Retrieves database credentials automatically
3. ✅ Exposes MySQL port 3306 if not already exposed
4. ✅ Tests database connectivity
5. ✅ Creates `LibreNMS-MySQL` datasource in Grafana
6. ✅ Verifies with test query

**Prerequisites:**
- SSH access to LibreNMS server (passwordless SSH recommended)
- `.env` file sourced or root/sudo access

#### Option B: Via Grafana UI (Manual)

1. Login to Grafana: `https://grafana.lab:3000`
   - Username: `admin`
   - Password: (from `.env` - `GRAFANA_ADMIN_PASSWORD`)

2. Navigate to **☰ Menu → Connections → Data sources**

3. Click **Add new data source**

4. Search for and select **MySQL**

5. Configure the datasource:
   - **Name:** `LibreNMS-MySQL`
   - **Host:** `<librenms-ip>:3306` (e.g., `10.1.10.58:3306`)
   - **Database:** `librenms`
   - **User:** `librenms`
   - **Password:** (from Step 2)
   - **Max open connections:** `5`
   - **Max idle connections:** `2`
   - **Connection Max Lifetime:** `14400` (4 hours)

6. Click **Save & Test**

**Expected result:**
```
✅ Database Connection OK
```

#### Option C: Via Grafana API

```bash
# On Grafana server
cd /root/containerized-grafana-deploy
source .env

curl -X POST -H "Content-Type: application/json" \
  -u admin:${GRAFANA_ADMIN_PASSWORD} \
  https://localhost:3000/api/datasources -k \
  -d '{
    "name": "LibreNMS-MySQL",
    "type": "mysql",
    "access": "proxy",
    "url": "<librenms-ip>:3306",
    "database": "librenms",
    "user": "librenms",
    "secureJsonData": {
      "password": "<librenms-db-password>"
    },
    "jsonData": {
      "maxOpenConns": 5,
      "maxIdleConns": 2,
      "connMaxLifetime": 14400
    }
  }'
```

**Replace:**
- `<librenms-ip>` with your LibreNMS server IP
- `<librenms-db-password>` with the password from Step 2

### Step 5: Verify Datasource Connection

1. After adding the datasource, the **Save & Test** button should show:
   ```
   ✅ Database Connection OK
   ```

2. If test fails, check:
   - LibreNMS database port is accessible from Grafana server
   - Database credentials are correct
   - Firewall allows traffic on port 3306
   - Database user has SELECT permissions on `librenms` database

### Step 6: Test with Sample Query

Navigate to **☰ Menu → Explore** in Grafana:

1. Select datasource: **LibreNMS-MySQL**

2. Switch to **Code** mode (top right)

3. Run a test query:

```sql
SELECT
  hostname,
  sysName,
  os,
  status,
  uptime
FROM devices
WHERE disabled = 0
LIMIT 10;
```

4. Click **Run query**

**Expected:** Table showing your LibreNMS monitored devices

**Sample output:**
```
hostname      | sysName          | os       | status | uptime
10.1.10.49    | s3560g-1.lab     | ios      | 1      | 8475600
10.1.10.45    | s3560g-2         | ios      | 1      | 7392845
10.1.10.56    | ciscoasa.lab     | asa      | 1      | 9234567
```

---

## Verification

### Verify Zabbix Data Flow

1. Login to Grafana: `https://grafana.lab:3000`

2. Navigate to **☰ Menu → Explore**

3. Select datasource: **Zabbix**

4. Create a simple query:
   - **Group:** Select any host group (e.g., `Linux servers`)
   - **Host:** Select a monitored host
   - **Item:** Select a metric (e.g., `CPU load`, `Memory usage`)

5. Click **Run query**

**Expected:** Graph showing recent data

**If "No Data":** See [Troubleshooting: Zabbix](#zabbix-connection-issues)

### Verify LibreNMS Data Flow

#### Check in Grafana Explore

1. Login to Grafana: `https://grafana.lab:3000`

2. Navigate to **☰ Menu → Explore**

3. Select datasource: **LibreNMS-MySQL**

4. Switch to **Code** mode

5. Run sample queries:

**Query 1: Device Count**
```sql
SELECT
  COUNT(*) as total_devices,
  SUM(CASE WHEN disabled = 0 THEN 1 ELSE 0 END) as active_devices,
  SUM(CASE WHEN disabled = 1 THEN 1 ELSE 0 END) as disabled_devices
FROM devices;
```

**Query 2: Device List with Status**
```sql
SELECT
  hostname,
  sysName,
  os,
  version,
  status,
  CASE WHEN status = 1 THEN 'Up' ELSE 'Down' END as status_text,
  FROM_UNIXTIME(last_polled) as last_polled_time
FROM devices
WHERE disabled = 0
ORDER BY last_polled DESC
LIMIT 20;
```

**Query 3: Port Statistics (Bandwidth)**
```sql
SELECT
  d.hostname,
  p.ifName,
  p.ifAlias,
  p.ifOperStatus,
  ROUND(p.ifInOctets_rate * 8 / 1000000, 2) as inbound_mbps,
  ROUND(p.ifOutOctets_rate * 8 / 1000000, 2) as outbound_mbps
FROM ports p
JOIN devices d ON p.device_id = d.device_id
WHERE p.ifOperStatus = 'up'
  AND d.disabled = 0
  AND (p.ifInOctets_rate > 0 OR p.ifOutOctets_rate > 0)
ORDER BY p.ifInOctets_rate DESC
LIMIT 20;
```

**Query 4: Storage Usage**
```sql
SELECT
  d.hostname,
  s.storage_descr,
  ROUND((s.storage_used / s.storage_size) * 100, 2) as used_percent,
  ROUND(s.storage_used / 1073741824, 2) as used_gb,
  ROUND(s.storage_size / 1073741824, 2) as total_gb
FROM storage s
JOIN devices d ON s.device_id = d.device_id
WHERE d.disabled = 0
  AND s.storage_size > 0
ORDER BY used_percent DESC
LIMIT 20;
```

6. Click **Run query** for each

**If "No Data":** See [Troubleshooting: LibreNMS](#librenms-connection-issues)

---

## Troubleshooting

### Zabbix Connection Issues

#### Test: Zabbix API not accessible

**Check from Grafana container:**

```bash
sudo podman exec grafana wget -qO- http://zabbix.lab/api_jsonrpc.php
```

**If connection fails:**
- Verify Zabbix URL is correct (check for subdirectory path)
- Ensure network connectivity: `ping zabbix.lab`
- Check firewall on Zabbix server allows incoming traffic

#### Test: Invalid API token

**Symptoms:**
- Grafana shows: "Unauthorized" or "Invalid API token"

**Solution:**
1. Verify token in Zabbix: **Administration → Users → API tokens**
2. Ensure token is **Enabled**
3. Check token hasn't expired
4. Generate a new token if needed
5. Update `.env` file and redeploy:

```bash
cd /root/containerized-grafana-deploy
sudo bash scripts/install.sh
```

#### Test: Wrong Zabbix URL format

**Common mistakes:**

```bash
# ❌ Wrong - missing api_jsonrpc.php
ZABBIX_URL=http://zabbix.lab

# ❌ Wrong - includes zabbix subdirectory when not needed
ZABBIX_URL=http://zabbix.lab/zabbix/api_jsonrpc.php

# ✅ Correct - direct to API endpoint
ZABBIX_URL=http://zabbix.lab/api_jsonrpc.php

# ✅ Correct - if in subdirectory
ZABBIX_URL=http://zabbix.lab/zabbix/api_jsonrpc.php
```

Test API directly:

```bash
curl -X POST http://zabbix.lab/api_jsonrpc.php \
  -H "Content-Type: application/json-rpc" \
  -d '{
    "jsonrpc": "2.0",
    "method": "apiinfo.version",
    "params": [],
    "id": 1
  }'
```

**Expected:** `{"jsonrpc":"2.0","result":"X.X.X","id":1}`

### LibreNMS: Connection Issues

#### Test: MySQL Port Not Accessible

**Check from Grafana server:**

```bash
# Test port connectivity
timeout 2 bash -c "echo > /dev/tcp/<librenms-ip>/3306" && echo "✅ Port reachable" || echo "❌ Port blocked"

# Check with telnet (if installed)
telnet <librenms-ip> 3306
```

**If connection fails:**
- Verify MySQL port is exposed in container configuration
- Check firewall on LibreNMS server:
  ```bash
  # On LibreNMS server
  sudo firewall-cmd --list-ports | grep 3306
  ```
- If firewall is blocking, add rule:
  ```bash
  sudo firewall-cmd --permanent --add-port=3306/tcp
  sudo firewall-cmd --reload
  ```

#### Test: Authentication Failed

**Symptoms:**
- Grafana shows: "Access denied for user 'librenms'@'<ip>'"

**Solution:**

1. Verify credentials are correct:
   ```bash
   # On LibreNMS server
   podman exec librenms env | grep -E '(DB_USER|DB_PASSWORD)'
   ```

2. Check MySQL user permissions:
   ```bash
   # On LibreNMS server (inside db container)
   podman exec librenms-db mysql -u root -p<root-password> -e \
     "SELECT User, Host FROM mysql.user WHERE User='librenms';"
   ```

3. If user can only connect from localhost, grant remote access:
   ```bash
   podman exec librenms-db mysql -u root -p<root-password> -e \
     "GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'%' IDENTIFIED BY '<password>';"
   podman exec librenms-db mysql -u root -p<root-password> -e "FLUSH PRIVILEGES;"
   ```

#### Test: Database Connection Works but No Data

**Check if LibreNMS has devices:**

```bash
# From Grafana server (via datasource query)
# Or on LibreNMS server:
podman exec librenms-db mysql -u librenms -p<password> librenms -e \
  "SELECT COUNT(*) as device_count FROM devices WHERE disabled=0;"
```

**If count is 0:**
- No devices have been added to LibreNMS yet
- Login to LibreNMS web UI and add devices: `http://<librenms-ip>/`

#### Debug: Test Query Directly

```bash
# From Grafana server (if mysql client installed)
mysql -h <librenms-ip> -u librenms -p<password> librenms -e "
  SELECT hostname, sysName, os, status
  FROM devices
  WHERE disabled=0
  LIMIT 5;
"
```

**Expected:** List of devices

**If query fails:**
- Check database name is correct (`librenms`)
- Verify user has SELECT permission on tables

### General Grafana Issues

#### Datasources Disappear After Container Restart

**Cause:** Volume persistence issue

**Check volumes:**

```bash
sudo podman volume inspect grafana-storage
ls -la /srv/obs/grafana/data
```

**Verify SELinux labels:**

```bash
ls -laZ /srv/obs/grafana/data
```

**Expected:** `container_file_t` context

**If incorrect:**

```bash
sudo chown -R 472:472 /srv/obs/grafana/data
sudo chcon -R -t container_file_t /srv/obs/grafana/data
```

#### Plugins Not Loading

**Check installed plugins:**

```bash
sudo podman exec grafana grafana cli plugins ls
```

**Expected:**
```
alexanderzobnin-zabbix-app @ X.X.X
```

**If missing:**
- Check `.env` has `GRAFANA_INSTALL_ZABBIX_PLUGIN=true`
- Redeploy: `sudo bash scripts/install.sh`
- Check logs: `sudo journalctl -u grafana -n 100 --no-pager`

---

## Recommended Dashboards

Once your datasources are connected and verified, import these community dashboards:

### Import Instructions

1. Navigate to **☰ Menu → Dashboards**
2. Click **New → Import**
3. Enter the Dashboard ID
4. Click **Load**
5. Select the appropriate datasource
6. Click **Import**

### Zabbix Dashboards

| Dashboard Name | ID | Description |
|----------------|-----|-------------|
| Zabbix System Status | `5363` | Overall Zabbix monitoring status |
| Zabbix Server | `12428` | Zabbix server performance metrics |
| Zabbix Host Overview | `12665` | Individual host monitoring |

### LibreNMS Dashboards

| Dashboard Name | ID | Description |
|----------------|-----|-------------|
| LibreNMS All-In-One | `15306` | Comprehensive LibreNMS overview |
| Network Device Traffic | `12633` | Interface bandwidth utilization |

**Note:** When importing LibreNMS dashboards:
- Select datasource: **InfluxDB-LibreNMS**
- May require query modifications to match your measurement names
- Refer to Flux documentation for query syntax

---

## Expected Metrics

### Zabbix Metrics

Available directly via Zabbix API:
- Host availability and status
- CPU, memory, disk usage
- Network interface statistics
- Application-specific metrics
- Triggers and alerts

### LibreNMS Metrics (via MySQL)

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `devices` | Network devices | `device_id`, `hostname`, `sysName`, `os`, `status`, `uptime`, `last_polled` |
| `ports` | Interface/port metrics | `ifName`, `ifAlias`, `ifInOctets_rate`, `ifOutOctets_rate`, `ifOperStatus` |
| `storage` | Disk/storage metrics | `storage_descr`, `storage_used`, `storage_size`, `storage_perc` |
| `device_perf` | Device performance | `xmt`, `rcv`, `loss`, `avg`, `min`, `max` (ping statistics) |
| `sensors` | Environmental sensors | `sensor_descr`, `sensor_current`, `sensor_type` (temp, humidity, etc.) |
| `mempools` | Memory usage | `mempool_used`, `mempool_free`, `mempool_total` |
| `processors` | CPU usage | `processor_usage`, `processor_descr` |

**Useful Joins:**
- `devices` ↔ `ports` via `device_id`
- `devices` ↔ `storage` via `device_id`
- `devices` ↔ `sensors` via `device_id`
- `devices` ↔ `mempools` via `device_id`
- `devices` ↔ `processors` via `device_id`

---

## Performance Considerations

### Zabbix
- **Query Optimization:** Use trends data for historical queries (> 7 days)
- **Cache TTL:** 1 hour (configured in datasource)
- **Timeout:** 30 seconds per query

### LibreNMS
- **Polling Frequency:** Default 5 minutes (data updates in MySQL immediately)
- **Query Performance:** Direct SQL queries are fast for recent data (<1 second)
- **Historical Data:** All data retained in MySQL (configure retention in LibreNMS)
- **Connection Pooling:** Max 5 connections to avoid overwhelming database
- **Recommendation:** Use time-based WHERE clauses to limit query scope for performance

---

## Security Notes

### Zabbix
- API tokens are stored securely in Grafana's encrypted database
- Use dedicated Grafana user in Zabbix with read-only permissions
- Rotate API tokens regularly
- Consider enabling HTTPS for Zabbix API

### LibreNMS → Grafana (MySQL)
- **Read-Only Access:** Configure Grafana datasource with SELECT-only permissions
- **Firewall:** Restrict MySQL port 3306 to Grafana server IP only:
  ```bash
  # On LibreNMS server
  sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<grafana-ip>" port port="3306" protocol="tcp" accept'
  sudo firewall-cmd --reload
  ```
- **SSL/TLS:** Consider using MySQL over SSL in production
- **Password Storage:** Credentials stored in Grafana's encrypted database
- **Best Practice:** Create dedicated read-only MySQL user for Grafana:
  ```sql
  CREATE USER 'grafana_ro'@'<grafana-ip>' IDENTIFIED BY '<password>';
  GRANT SELECT ON librenms.* TO 'grafana_ro'@'<grafana-ip>';
  FLUSH PRIVILEGES;
  ```

---

## Support & Additional Resources

### Log Locations

**Grafana:**
```bash
sudo journalctl -u grafana -n 100 --no-pager
sudo podman logs grafana --tail 100
```

**InfluxDB:**
```bash
sudo journalctl -u influxdb -n 100 --no-pager
sudo podman logs influxdb --tail 100
```

**LibreNMS:**
```bash
docker exec librenms tail -f /opt/librenms/logs/librenms.log
```

### Health Check

Run comprehensive stack health check:

```bash
cd /root/containerized-grafana-deploy
sudo bash scripts/health-check.sh
```

### Documentation

- **Zabbix Plugin:** https://grafana.com/docs/plugins/alexanderzobnin-zabbix-app/
- **InfluxDB Flux:** https://docs.influxdata.com/flux/
- **LibreNMS InfluxDB:** https://docs.librenms.org/Extensions/metrics/

---

**Last Updated:** 2026-02-05
**Architecture:** Direct Query (Grafana → LibreNMS MySQL)
**Grafana Version:** Latest (containerized)
**Status:** Production Ready ✅
