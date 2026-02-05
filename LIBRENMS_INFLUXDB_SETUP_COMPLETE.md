# LibreNMS → InfluxDB Integration - Setup Complete ✅

**Date:** 2026-02-05
**Status:** Configuration applied and persistent

---

## What Was Done

### 1. Created Persistent InfluxDB Configuration
- **Location:** `/opt/librenms/data/config/influxdb.php` (on LibreNMS server 10.1.10.58)
- **Mount:** This directory is bind-mounted, so the config **persists across container restarts**
- **Owner:** `cpaquin:cpaquin` (matches LibreNMS container user)

### 2. Configuration Details

```php
// InfluxDB v2 Settings
$config['influxdb']['enable'] = true;
$config['influxdb']['host'] = '10.1.10.52';
$config['influxdb']['port'] = 8086;
$config['influxdb']['version'] = 2;
$config['influxdb']['organization'] = 'observability';
$config['influxdb']['db'] = 'librenms';
$config['influxdb']['password'] = '7/0UL32+BW/lCLq4Q/Rcn6i/skmHAdXNlcoa7mk5ZBo=';

// Metrics to Export
$config['influxdb']['enable_poller'] = true;   // Device stats
$config['influxdb']['enable_port'] = true;     // Interface stats
$config['influxdb']['enable_storage'] = true;  // Disk usage
$config['influxdb']['enable_ping'] = true;     // Latency/loss

// Performance
$config['influxdb']['batch'] = true;
$config['influxdb']['batch_size'] = 1000;
```

### 3. Verification Completed

✅ Configuration loaded into LibreNMS
✅ LibreNMS containers running
✅ Config persists across restarts
✅ InfluxDB connectivity confirmed

---

## Next Steps (Wait 5-10 Minutes)

LibreNMS polls devices **every 5 minutes**. After the next poll cycle:

### Check Data in Grafana

1. **Open Grafana:** `https://10.1.10.52:3000`
2. **Navigate to:** Explore → Select **InfluxDB-LibreNMS** datasource
3. **Run this Flux query:**

```flux
from(bucket: "librenms")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement != "test")
  |> limit(n: 100)
```

### Expected Metrics

You should see measurements for:
- **Device stats:** CPU, memory, uptime
- **Interface stats:** Traffic (bits/sec), errors, discards
- **Storage:** Disk usage percentages
- **Ping:** Response time, packet loss

---

## Troubleshooting

### No Data After 10 Minutes?

**Check LibreNMS logs:**
```bash
ssh root@10.1.10.58 "podman logs librenms | grep -i influx"
```

**Verify config still loaded:**
```bash
ssh root@10.1.10.58 "podman exec -u librenms librenms php /opt/librenms/lnms config:get influxdb.enable"
```
Should return: `true`

**Check InfluxDB connectivity from LibreNMS:**
```bash
ssh root@10.1.10.58 "podman exec librenms curl -I http://10.1.10.52:8086/health"
```
Should return: `HTTP/1.1 200 OK`

### Restart LibreNMS (if needed)

```bash
ssh root@10.1.10.58 "podman restart librenms librenms-dispatcher"
```

---

## Script Location (For Future Reference)

If you need to reconfigure or run on another LibreNMS instance:

```bash
cd /root/containerized-grafana-deploy
source .env
./scripts/remote-configure-librenms.sh <librenms-ip> [ssh-user]
```

**Note:** The automated script has a validation bug (reports failure even on success). Use this manual method for now.

---

## Architecture Summary

```
┌─────────────┐  poll    ┌─────────────┐  push    ┌─────────────┐  query   ┌─────────────┐
│   Network   │◄────────►│  LibreNMS   │─────────►│  InfluxDB   │◄─────────│   Grafana   │
│   Devices   │  SNMP    │ (10.1.10.58)│  HTTP    │(10.1.10.52) │   Flux   │(10.1.10.52) │
└─────────────┘          └─────────────┘          └─────────────┘          └─────────────┘
```

**Data Flow:**
1. LibreNMS polls network devices via SNMP
2. LibreNMS pushes metrics to InfluxDB every poll cycle
3. Grafana queries InfluxDB using Flux language
4. Dashboards display real-time network metrics

---

## Status: ✅ READY FOR DATA

Configuration is complete and persistent. Data will flow automatically starting with the next LibreNMS poll cycle (within 5-10 minutes).
