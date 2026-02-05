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

### LibreNMS Architecture (Push-to-TSDB)

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  LibreNMS   │──push──>│  InfluxDB   │◄─query──│   Grafana   │
│  (Poller)   │         │  (TSDB)     │         │             │
└─────────────┘         └─────────────┘         └─────────────┘
```

- **Method:** LibreNMS pushes metrics to InfluxDB, Grafana queries InfluxDB
- **Storage:** InfluxDB v2.x bucket `librenms`
- **Query Language:** Flux
- **Datasource:** Auto-provisioned as `InfluxDB-LibreNMS`
- **NO Plugin Required:** Uses native InfluxDB datasource

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
- Access to modify LibreNMS configuration
- Network connectivity from LibreNMS to InfluxDB (port 8086)

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

LibreNMS does NOT connect directly to Grafana. Instead:
1. **LibreNMS** polls network devices (SNMP, etc.)
2. **LibreNMS** pushes metrics to **InfluxDB** (on Grafana server)
3. **Grafana** queries **InfluxDB** using Flux language

**No LibreNMS plugin required** - uses the pre-provisioned `InfluxDB-LibreNMS` datasource.

### Step 1: Verify InfluxDB Datasource in Grafana

The InfluxDB datasource is automatically provisioned during deployment.

1. Login to Grafana: `https://grafana.lab:3000`

2. Navigate to **☰ Menu → Connections → Data sources**

3. Click on **InfluxDB-LibreNMS** datasource

4. Verify configuration:
   - **Query Language:** Flux
   - **URL:** `http://influxdb:8086`
   - **Organization:** `observability`
   - **Default Bucket:** `librenms`
   - **Token:** (configured from `.env`)

5. Click **Save & Test**

**Expected result:**
```
✅ 1 buckets found
```

### Step 2: Configure LibreNMS to Push Metrics

You need to configure your LibreNMS instance to push data to InfluxDB.

#### Get Required Credentials

On your **Grafana server**, retrieve the credentials:

```bash
cd /root/containerized-grafana-deploy
source .env

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "LibreNMS → InfluxDB Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "InfluxDB Server: $(hostname -I | awk '{print $1}')"
echo "InfluxDB Port: 8086"
echo "Protocol: HTTP"
echo "Organization: ${INFLUXDB_ORG}"
echo "Bucket: ${INFLUXDB_BUCKET}"
echo "Token: ${INFLUXDB_TOKEN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

**Copy these values** - you'll need them for LibreNMS configuration.

#### Option A: Automated Configuration (Recommended)

If your LibreNMS is running in containers with bind-mounted config:

1. Copy the helper script to your LibreNMS server:

```bash
# From Grafana server
cd /root/containerized-grafana-deploy
scp helper/configure-librenms-influxdb.sh root@<librenms-ip>:/tmp/
```

2. SSH to your LibreNMS server:

```bash
ssh root@<librenms-ip>
chmod +x /tmp/configure-librenms-influxdb.sh
```

3. Edit the script to include your credentials (use values from Step 2)

4. Run the script:

```bash
/tmp/configure-librenms-influxdb.sh
```

The script will:
- Detect your LibreNMS container and config location
- Backup existing configuration
- Add InfluxDB v2 configuration
- Test connectivity to InfluxDB
- Restart the LibreNMS container
- Trigger a test poll

#### Option B: Manual Configuration

##### 1. Locate LibreNMS Config Directory

Find your LibreNMS config file:

```bash
# If using Docker
docker inspect librenms | grep -A 10 Mounts | grep config

# If using Podman
podman inspect librenms | grep -A 10 Mounts | grep config
```

Common locations:
- `/opt/librenms/config/config.php`
- `/var/lib/librenms/config/config.php`
- Custom mount point from your compose/quadlet file

##### 2. Backup Existing Config

```bash
cp /path/to/librenms/config/config.php /path/to/librenms/config/config.php.backup
```

##### 3. Add InfluxDB Configuration

Edit `config.php` and add **before the closing `?>` tag**:

```php
// ═══════════════════════════════════════════════════════════════
// InfluxDB v2 Configuration for Grafana Observability Stack
// ═══════════════════════════════════════════════════════════════

// Enable InfluxDB export
$config['influxdb']['enable'] = true;

// Connection settings
$config['influxdb']['transport'] = 'http';  // Use 'https' if SSL configured
$config['influxdb']['host'] = '<grafana-server-ip>';
$config['influxdb']['port'] = 8086;
$config['influxdb']['timeout'] = 5;
$config['influxdb']['verifySSL'] = false;

// InfluxDB v2 authentication
$config['influxdb']['version'] = 2;
$config['influxdb']['organization'] = 'observability';
$config['influxdb']['db'] = 'librenms';  // This is the bucket name in v2
$config['influxdb']['username'] = '';  // Leave empty for token auth
$config['influxdb']['password'] = '<your-influxdb-token>';

// Data export options
$config['influxdb']['enable_poller'] = true;    // Device polling statistics
$config['influxdb']['enable_port'] = true;      // Port/interface metrics
$config['influxdb']['enable_storage'] = true;   // Storage/disk metrics
$config['influxdb']['enable_ping'] = true;      // Ping response times

// Optional: Performance tuning
$config['influxdb']['batch'] = true;            // Batch writes for efficiency
$config['influxdb']['batch_size'] = 1000;       // Records per batch
```

**Replace:**
- `<grafana-server-ip>` with your Grafana server's IP address
- `<your-influxdb-token>` with the token from Step 2

##### 4. Test Connectivity

From inside the LibreNMS container:

```bash
# Access container
docker exec -it librenms bash
# OR
podman exec -it librenms bash

# Test InfluxDB health endpoint
curl -v http://<grafana-server-ip>:8086/health

# Test write access (replace <token> with your token)
curl -v -X POST "http://<grafana-server-ip>:8086/api/v2/write?org=observability&bucket=librenms" \
  -H "Authorization: Token <your-influxdb-token>" \
  -H "Content-Type: text/plain" \
  --data-binary "test,host=librenms value=1"
```

**Expected response:** HTTP 204 No Content (success)

##### 5. Restart LibreNMS Container

```bash
# Docker Compose
docker-compose restart librenms

# Standalone Docker
docker restart librenms

# Podman
podman restart librenms

# Systemd (if using Quadlet)
systemctl restart librenms
```

##### 6. Validate Configuration

```bash
# Access container
docker exec -it librenms bash

# Run validation
cd /opt/librenms
./validate.php | grep -i influx

# Manually trigger polling (with debug output)
./poller.php -d -h all 2>&1 | grep -i influx
```

Watch for InfluxDB-related messages confirming data is being sent.

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

#### Check Data in InfluxDB (from Grafana server)

```bash
# Query recent LibreNMS data
curl -s "http://localhost:8086/api/v2/query?org=observability" \
  -H "Authorization: Token $(grep INFLUXDB_TOKEN .env | cut -d= -f2)" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket:"librenms") |> range(start: -10m) |> limit(n: 10)'

# List measurements (should show: poller, ports, storage, ping)
curl -s "http://localhost:8086/api/v2/query?org=observability" \
  -H "Authorization: Token $(grep INFLUXDB_TOKEN .env | cut -d= -f2)" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "influxdata/influxdb/schema"
      schema.measurements(bucket: "librenms")'
```

#### Check in Grafana Explore

1. Login to Grafana: `https://grafana.lab:3000`

2. Navigate to **☰ Menu → Explore**

3. Select datasource: **InfluxDB-LibreNMS**

4. Ensure **Flux** language is selected (top right)

5. Run test query:

```flux
from(bucket: "librenms")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "poller")
  |> limit(n: 100)
```

6. Click **Run query**

**Expected measurements in LibreNMS data:**
- `poller` - Device polling statistics
- `ports` - Interface/port metrics
- `storage` - Disk usage metrics
- `ping` - Response time data

**If "No Data":** See [Troubleshooting: LibreNMS](#librenms-no-data-in-influxdb)

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

### LibreNMS: No Data in InfluxDB

#### Check: LibreNMS Container Logs

```bash
# On LibreNMS server
docker logs librenms --tail 100 | grep -i influx
# OR
podman logs librenms --tail 100 | grep -i influx
```

**Look for:**
- ✅ `InfluxDB: Successfully sent metrics`
- ❌ `InfluxDB: Connection refused`
- ❌ `InfluxDB: Authentication failed`
- ❌ `InfluxDB: Bucket not found`

#### Check: Connectivity from LibreNMS to InfluxDB

```bash
# From LibreNMS server (host)
curl http://<grafana-server-ip>:8086/health

# From inside LibreNMS container
docker exec librenms curl http://<grafana-server-ip>:8086/health
```

**Expected:** `{"name":"influxdb","message":"ready for queries and writes","status":"pass"}`

**If connection refused:**
- Check InfluxDB is running: `sudo systemctl status influxdb` (on Grafana server)
- Check firewall allows LibreNMS IP: `sudo firewall-cmd --list-rich-rules | grep 8086`
- Verify LibreNMS IP matches firewall rule

#### Check: Authentication Issues

```bash
# Test write access (replace values)
curl -v -X POST "http://<grafana-server-ip>:8086/api/v2/write?org=observability&bucket=librenms" \
  -H "Authorization: Token <your-token>" \
  -H "Content-Type: text/plain" \
  --data-binary "test,host=librenms value=1"
```

**Expected:** HTTP 204 No Content

**If 401 Unauthorized:**
- Token is incorrect or expired
- Regenerate token in InfluxDB if needed

**If 404 Not Found:**
- Bucket name is wrong (should be `librenms`)
- Verify bucket exists:

```bash
# On Grafana server
sudo podman exec influxdb influx bucket list --org observability
```

#### Check: LibreNMS Config Not Loaded

```bash
# Inside LibreNMS container
docker exec librenms bash -c "cd /opt/librenms && php -r \"include 'config.php'; var_dump(\$config['influxdb']);\""
```

**Expected:** Should display the InfluxDB configuration array

**If empty or errors:**
- Config file syntax error (check for missing semicolons, quotes)
- Config not in correct location
- Need to restart container after config change

#### Debug: Force Polling with Debug Output

```bash
# Inside LibreNMS container
docker exec librenms bash -c "cd /opt/librenms && ./poller.php -d -h 1 2>&1 | grep -i influx"
```

Watch for InfluxDB write attempts and any errors.

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

### LibreNMS Metrics (via InfluxDB)

| Measurement | Description | Key Fields |
|-------------|-------------|------------|
| `poller` | Device polling statistics | `device_id`, `poller_group`, `polling_time` |
| `ports` | Interface/port metrics | `ifInOctets`, `ifOutOctets`, `ifInErrors`, `ifOutErrors` |
| `storage` | Disk/storage metrics | `storage_used`, `storage_free`, `storage_perc` |
| `ping` | Response time data | `ping_time`, `packet_loss` |

---

## Performance Considerations

### Zabbix
- **Query Optimization:** Use trends data for historical queries (> 7 days)
- **Cache TTL:** 1 hour (configured in datasource)
- **Timeout:** 30 seconds per query

### LibreNMS
- **Polling Frequency:** Default 5 minutes
- **Batch Size:** 1000 records per batch
- **Network Latency:** ~1-2ms on same subnet
- **InfluxDB Retention:** 1 year (configured in observability stack)

---

## Security Notes

### Zabbix
- API tokens are stored securely in Grafana's encrypted database
- Use dedicated Grafana user in Zabbix with read-only permissions
- Rotate API tokens regularly
- Consider enabling HTTPS for Zabbix API

### LibreNMS → InfluxDB
- Token provides read-write access to `librenms` bucket only
- Firewall restricts InfluxDB access to LibreNMS IP only
- Consider using SSL/TLS in production (change `transport` to `https`)
- Token is stored in LibreNMS config.php (protect with file permissions)

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
**Architecture:** Push-to-TSDB (LibreNMS → InfluxDB → Grafana)
**Grafana Version:** Latest (containerized)
**Status:** Production Ready ✅
