# 📡 LibreNMS Integration Guide

Complete guide for integrating LibreNMS with the Grafana Observability Stack via InfluxDB 2.x.

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Configuration Steps](#configuration-steps)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Security Considerations](#security-considerations)

---

## Architecture Overview

### Data Flow

```text
┌─────────────┐         HTTP POST          ┌──────────────┐       Flux Queries
│  LibreNMS   │───────────────────────────►│  InfluxDB    │◄──────────────────┐
│     VM      │  Metrics Push (port 8086)  │     2.x      │                   │
└─────────────┘                             └──────────────┘                   │
  10.x.x.x                                   Container                         │
                                             (obs-net)                         │
                                                                               │
                                             ┌──────────────┐                 │
                                             │   Grafana    │─────────────────┘
                                             │              │  Visualization
                                             └──────────────┘
                                              Container
                                              (obs-net)
```

### Key Principles

- ✅ **LibreNMS is the source:** Collects network metrics via SNMP
- ✅ **InfluxDB is the TSDB:** Stores time-series data
- ✅ **Grafana is the visualization layer:** Queries InfluxDB using Flux

**Important:**
- ❌ Grafana does NOT query LibreNMS directly
- ❌ LibreNMS database is NOT accessed by Grafana
- ❌ Prometheus does NOT scrape LibreNMS

---

## Prerequisites

### On Grafana VM

- ✅ Observability stack deployed (`./scripts/install.sh` completed)
- ✅ InfluxDB container running and healthy
- ✅ Port 8086 accessible from LibreNMS VM
- ✅ Firewall configured to allow LibreNMS → InfluxDB traffic

### On LibreNMS VM

- ✅ LibreNMS installed and operational
- ✅ Network connectivity to Grafana VM port 8086
- ✅ InfluxDB plugin/export feature available

### Required Information

From your `.env` file on Grafana VM:

```bash
INFLUXDB_URL=http://<grafana-vm-ip>:8086
INFLUXDB_ORG=observability
INFLUXDB_BUCKET=librenms
INFLUXDB_TOKEN=<your-generated-token>
```

---

## Configuration Steps

### Step 1: Verify InfluxDB is Running

On **Grafana VM:**

```bash
# Check InfluxDB service status
systemctl status influxdb.service

# Verify InfluxDB health
curl http://localhost:8086/health

# Expected output:
# {"status":"pass","message":"ready for queries and writes"}
```

### Step 2: Get Configuration Values

On **Grafana VM:**

```bash
# Display configuration values needed for LibreNMS
cd /root/containerized-grafana-deploy
source .env

echo "InfluxDB URL: ${INFLUXDB_URL}"
echo "Organization: ${INFLUXDB_ORG}"
echo "Bucket: ${INFLUXDB_BUCKET}"
echo "Token: ${INFLUXDB_TOKEN}"
```

**Copy these values** - you'll need them for LibreNMS configuration.

### Step 3: Test Connectivity from LibreNMS

On **LibreNMS VM:**

```bash
# Replace <grafana-vm-ip> with actual IP
GRAFANA_IP="10.1.10.100"  # Example - change this

# Test health endpoint
curl http://${GRAFANA_IP}:8086/health

# If successful, you should see:
# {"status":"pass","message":"ready for queries and writes"}

# If connection fails, check:
# - Network routing between VMs
# - Firewall rules on Grafana VM
# - InfluxDB service is running
```

### Step 4: Configure InfluxDB Export in LibreNMS

#### Via Web UI

1. **Login to LibreNMS** as administrator

2. **Navigate to Settings:**
   - Click **Settings** (gear icon)
   - Go to **Plugins** section
   - Find **InfluxDB** or **InfluxDB v2** plugin

3. **Enable and Configure:**

   | Setting | Value | Example |
   |---------|-------|---------|
   | **Enable** | ✅ Checked | - |
   | **URL** | From `INFLUXDB_URL` | `http://10.1.10.100:8086` |
   | **Organization** | From `INFLUXDB_ORG` | `observability` |
   | **Bucket** | From `INFLUXDB_BUCKET` | `librenms` |
   | **Token** | From `INFLUXDB_TOKEN` | `<your-token>` |
   | **Version** | v2 | InfluxDB 2.x |

4. **Test Connection:**
   - Click **Test** or **Save & Test**
   - Should show: ✅ "Connection successful"

#### Save Configuration

#### Via Configuration File (Alternative)

Edit `/opt/librenms/config.php` or create `/opt/librenms/config.d/influxdb.php`:

```php
<?php
// InfluxDB 2.x Configuration
$config['influxdb']['enable'] = true;
$config['influxdb']['transport'] = 'https';  // or 'http'
$config['influxdb']['host'] = '10.1.10.100';
$config['influxdb']['port'] = 8086;
$config['influxdb']['token'] = 'your-influxdb-token-here';
$config['influxdb']['organization'] = 'observability';
$config['influxdb']['bucket'] = 'librenms';
$config['influxdb']['timeout'] = 5;
?>
```

### Step 5: Enable Poller Module

Ensure LibreNMS poller is configured to export metrics:

```bash
# On LibreNMS VM
cd /opt/librenms

# Check poller modules
./lnms config:get poller.modules

# Enable InfluxDB module if not already enabled
./lnms config:set poller.modules.influxdb true
```

### Step 6: Force Poller Run (Optional)

Trigger immediate data export:

```bash
# On LibreNMS VM
cd /opt/librenms
./poller.php -h all -m influxdb -d
```

Watch for:
- ✅ "InfluxDB: Connected"
- ✅ "InfluxDB: Writing metrics"
- ❌ Connection errors or timeouts

---

## Verification

### 1. Check LibreNMS Logs

On **LibreNMS VM:**

```bash
# View poller logs
tail -f /opt/librenms/logs/librenms.log | grep -i influx

# Look for:
# - "InfluxDB write successful"
# - Metric counts
# - No error messages
```

### 2. Query InfluxDB Directly

On **Grafana VM:**

```bash
# Enter InfluxDB container
podman exec -it influxdb bash

# Run Flux query
influx query '
  from(bucket: "librenms")
    |> range(start: -5m)
    |> limit(n: 10)
' --org observability

# Should show recent LibreNMS metrics
```

### 3. Verify in Grafana UI

1. **Open Grafana:** `http://<grafana-vm-ip>:3000`

2. **Navigate to Explore:**
   - Click **Explore** (compass icon)
   - Select datasource: **InfluxDB-LibreNMS**

3. **Run Test Query:**

   **Flux Query:**

   ```flux
   from(bucket: "librenms")
     |> range(start: -1h)
     |> filter(fn: (r) => r["_measurement"] == "interface")
     |> limit(n: 100)
   ```

4. **Expected Results:**
   - Tables with device metrics
   - Interface statistics
   - Recent timestamps

### 4. Check Data Freshness

```bash
# On Grafana VM
podman exec influxdb influx query '
  from(bucket: "librenms")
    |> range(start: -1h)
    |> last()
' --org observability

# Verify _time is recent (within last 5 minutes)
```

---

## Troubleshooting

### Issue 1: Connection Timeout from LibreNMS

**Symptoms:**
- LibreNMS poller shows "Connection timeout"
- Cannot reach InfluxDB from LibreNMS VM

**Solutions:**

1. **Check network connectivity:**

   ```bash
   # From LibreNMS VM
   ping <grafana-vm-ip>
   telnet <grafana-vm-ip> 8086
   ```

2. **Verify firewall rules:**

   ```bash
   # On Grafana VM
   sudo firewall-cmd --list-rich-rules | grep 8086

   # Should show rule allowing LibreNMS IP
   ```

3. **Add firewall rule if missing:**

   ```bash
   # On Grafana VM (replace x.x.x.x with LibreNMS IP)
   sudo firewall-cmd --permanent \
     --add-rich-rule='rule family="ipv4" source address="x.x.x.x/32" \
     port port="8086" protocol="tcp" accept'
   sudo firewall-cmd --reload
   ```

### Issue 2: Authentication Failed

**Symptoms:**
- "401 Unauthorized" in LibreNMS logs
- "Token authentication failed"

**Solutions:**

1. **Verify token in .env:**

   ```bash
   # On Grafana VM
   grep INFLUXDB_TOKEN /root/containerized-grafana-deploy/.env
   ```

2. **Check token in InfluxDB:**

   ```bash
   podman exec influxdb influx auth list --org observability
   ```

3. **Regenerate token if needed:**

   ```bash
   # In InfluxDB container
   podman exec -it influxdb bash
   influx auth create \
     --org observability \
     --read-buckets \
     --write-buckets \
     --description "LibreNMS Export"
   ```

   Copy new token and update both:
   - `.env` on Grafana VM
   - LibreNMS configuration

### Issue 3: No Data in Grafana

**Symptoms:**
- InfluxDB connection successful
- But no metrics visible in Grafana

**Solutions:**

1. **Verify bucket has data:**

   ```bash
   podman exec influxdb influx query '
     buckets()
       |> filter(fn: (r) => r.name == "librenms")
   ' --org observability
   ```

2. **Check LibreNMS is actually polling:**

   ```bash
   # On LibreNMS VM
   cd /opt/librenms
   ./poller.php -h all -m influxdb -d
   ```

3. **Verify datasource in Grafana:**
   - Configuration → Data Sources → InfluxDB-LibreNMS
   - Click "Save & Test"
   - Should show: ✅ "Data source is working"

4. **Check time range in Grafana:**
   - Ensure query time range covers period when data exists
   - Try: "Last 24 hours" or "Last 7 days"

### Issue 4: Metric Names Don't Match

**Symptoms:**
- Queries return no results
- Metric names in InfluxDB don't match expected names

**Solutions:**

1. **Discover actual metric names:**

   ```bash
   podman exec influxdb influx query '
     import "influxdata/influxdb/schema"
     schema.measurements(bucket: "librenms")
   ' --org observability
   ```

2. **Inspect measurement structure:**

   ```flux
   from(bucket: "librenms")
     |> range(start: -1h)
     |> limit(n: 1)
     |> yield()
   ```

3. **Update Grafana queries** to match actual measurement names

---

## Performance Tuning

### InfluxDB Optimization

For high-volume LibreNMS deployments:

**1. Increase InfluxDB Memory:**

Edit `/root/containerized-grafana-deploy/quadlets/influxdb.container`:

```ini
[Container]
Memory=8G
MemorySwap=8G
```

Apply:

```bash
systemctl daemon-reload
systemctl restart influxdb.service
```

**2. Adjust Bucket Retention:**

```bash
# Reduce retention if disk space is limited
podman exec influxdb influx bucket update \
  --name librenms \
  --retention 30d \
  --org observability
```

**3. Enable Compression:**

Already enabled by default in InfluxDB 2.x.

### LibreNMS Tuning

**1. Reduce Export Frequency:**

If metrics update too frequently:

```bash
# On LibreNMS VM
# Edit poller interval in LibreNMS config
# Default: 5 minutes
# Consider: 10 minutes for large deployments
```

**2. Filter Exported Metrics:**

Only export critical metrics to reduce load:

```php
// In LibreNMS config.php
$config['influxdb']['include'] = [
    'device',
    'interface',
    'processor',
    'memory'
];
```

---

## Security Considerations

### Network Security

1. **Restrict InfluxDB Access:**
   - ✅ Only allow LibreNMS VM IP
   - ❌ Do NOT expose port 8086 to public internet
   - ✅ Use firewall rich rules

2. **Use HTTPS (Recommended):**

   If LibreNMS and Grafana VM communicate over untrusted networks:

   - Configure TLS for InfluxDB
   - Update `INFLUXDB_URL` to use `https://`
   - Install valid SSL certificate

### Token Management

1. **Token Rotation:**

   Rotate InfluxDB token periodically:

   ```bash
   # Generate new token
   podman exec influxdb influx auth create \
     --org observability \
     --write-buckets \
     --description "LibreNMS Export $(date +%Y-%m-%d)"

   # Update .env and LibreNMS config
   # Delete old token
   ```

2. **Least Privilege:**

   Token should only have:
   - ✅ Write access to `librenms` bucket
   - ❌ NO admin permissions
   - ❌ NO read access to other buckets

3. **Secure Storage:**
   - ✅ Store token in `.env` (gitignored)
   - ✅ Restrict `.env` file permissions: `chmod 600 .env`
   - ❌ Do NOT commit tokens to git

### Monitoring

1. **Set up alerts for:**
   - InfluxDB disk space > 80%
   - Failed LibreNMS push attempts
   - Authentication failures

2. **Regular health checks:**

   ```bash
   # Add to cron
   */5 * * * * curl -f http://localhost:8086/health || echo "InfluxDB down!"
   ```

---

## Dashboard Examples

### Example Grafana Dashboard Queries

**1. Interface Traffic (Bits/sec):**

```flux
from(bucket: "librenms")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "interface")
  |> filter(fn: (r) => r["_field"] == "ifInOctets_rate" or r["_field"] == "ifOutOctets_rate")
  |> map(fn: (r) => ({ r with _value: r._value * 8.0 }))
```

**2. Device Availability:**

```flux
from(bucket: "librenms")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "device")
  |> filter(fn: (r) => r["_field"] == "uptime")
  |> last()
```

**3. Top Interfaces by Utilization:**

```flux
from(bucket: "librenms")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "interface")
  |> filter(fn: (r) => r["_field"] == "ifInOctets_rate")
  |> top(n: 10, columns: ["_value"])
```

---

## Related Documentation

- [README.md](../README.md) - Main installation guide
- [VARIABLES_REFERENCE.md](../VARIABLES_REFERENCE.md) - Environment variables
- [TUNING.md](TUNING.md) - Performance tuning guide
- [InfluxDB 2.x Documentation](https://docs.influxdata.com/influxdb/v2/)
- [LibreNMS Documentation](https://docs.librenms.org/)

---

## Support

For issues specific to:

- **LibreNMS Integration:** Check this guide and LibreNMS documentation
- **InfluxDB Issues:** See `journalctl -u influxdb.service`
- **Grafana Queries:** Consult Flux query documentation
- **Network/Firewall:** Review firewall rules and connectivity

---

**Last Updated:** 2026-01-28
**Status:** ✅ Production Ready
