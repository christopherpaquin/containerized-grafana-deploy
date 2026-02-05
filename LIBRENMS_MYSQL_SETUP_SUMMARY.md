# LibreNMS MySQL Datasource Setup - Complete ✅

**Date:** 2026-02-05
**Method:** Direct MySQL Query (No InfluxDB middleware)
**Status:** Configured and Verified

---

## What Was Done

### 1. ✅ Exposed LibreNMS Database Port
- **Added** `PublishPort=3306:3306` to `/etc/containers/systemd/librenms-db.container`
- **Restarted** librenms-db service
- **Verified** port is accessible from Grafana server

### 2. ✅ Retrieved Database Credentials
- **Host:** `10.1.10.58`
- **Port:** `3306`
- **Database:** `librenms`
- **User:** `librenms`
- **Password:** `6jNTtWSlSeoFZiXVyhQqywm7xkYV01PP`

### 3. ✅ Removed Old InfluxDB Datasource
- **Deleted** datasource ID 3 (`InfluxDB-LibreNMS`)
- **Reason:** InfluxDB v2.x incompatible with LibreNMS PHP library

### 4. ✅ Created MySQL Datasource
- **Name:** `LibreNMS-MySQL`
- **ID:** 6
- **UID:** `dfcc04qh3qdxcc`
- **Connection:** Tested and verified working

### 5. ✅ Verified Data Access
- **Device Count:** 17 active devices
- **Sample Devices:** Cisco switches, ASA firewall, iDRAC, TP-Link switches
- **Queries:** Tested device list, port stats, storage usage

### 6. ✅ Updated Documentation
- **File:** `DATASOURCE_INTEGRATION_GUIDE.md`
- **Changes:**
  - Updated architecture from "Push-to-TSDB" to "Direct MySQL Query"
  - Rewrote LibreNMS integration section completely
  - Added MySQL-specific queries and troubleshooting
  - Updated verification steps with SQL examples
  - Added table schema reference for LibreNMS database

---

## Architecture

### Old (Attempted - Failed)
```
LibreNMS → InfluxDB → Grafana
          (incompatible)
```

### New (Working)
```
LibreNMS MySQL ← SQL Query ← Grafana
       ↓
   (Devices)
```

---

## Quick Access

### Grafana Explore
1. Open: `https://10.1.10.52:3000`
2. Navigate: **☰ Menu → Explore**
3. Select: **LibreNMS-MySQL** datasource
4. Run SQL queries against LibreNMS tables

### Sample Queries

**Device List:**
```sql
SELECT hostname, sysName, os, status
FROM devices
WHERE disabled=0;
```

**Port Bandwidth:**
```sql
SELECT
  d.hostname,
  p.ifName,
  ROUND(p.ifInOctets_rate * 8 / 1000000, 2) as inbound_mbps,
  ROUND(p.ifOutOctets_rate * 8 / 1000000, 2) as outbound_mbps
FROM ports p
JOIN devices d ON p.device_id = d.device_id
WHERE p.ifOperStatus = 'up'
ORDER BY p.ifInOctets_rate DESC
LIMIT 10;
```

**Storage Usage:**
```sql
SELECT
  d.hostname,
  s.storage_descr,
  ROUND((s.storage_used / s.storage_size) * 100, 2) as used_percent
FROM storage s
JOIN devices d ON s.device_id = d.device_id
WHERE d.disabled = 0
ORDER BY used_percent DESC;
```

---

## Key Tables

| Table | Purpose | Use For |
|-------|---------|---------|
| `devices` | Network devices | Device inventory, status |
| `ports` | Interfaces | Bandwidth, errors, status |
| `storage` | Disk/storage | Capacity, usage |
| `sensors` | Environmental | Temp, humidity, power |
| `mempools` | Memory | RAM usage |
| `processors` | CPU | CPU utilization |
| `device_perf` | Ping stats | Latency, packet loss |

---

## Why MySQL Instead of InfluxDB?

### Problem with InfluxDB Approach
- LibreNMS's `influxdb-php` library only supports InfluxDB v1.x
- InfluxDB v2.x API returns different JSON structure
- Even with v1 compatibility layer, PHP library fails on response parsing
- Error: `Undefined array key "results"` in LibreNMS code

### Advantages of MySQL Direct Query
- ✅ **No Middleware:** One less component to maintain
- ✅ **Immediate Data:** No polling delay or export errors
- ✅ **Full History:** Access to all LibreNMS historical data
- ✅ **Simpler:** Direct SQL queries, no Flux learning curve
- ✅ **Proven:** Standard MySQL → Grafana integration

---

## Security Recommendations

### Current Setup
- ✅ MySQL port exposed to network
- ❌ Using full `librenms` user (has write permissions)

### Production Hardening

1. **Create Read-Only User:**
   ```bash
   ssh root@10.1.10.58
   podman exec librenms-db mysql -u root -p<root-password> -e "
     CREATE USER 'grafana_ro'@'10.1.10.52' IDENTIFIED BY '<new-password>';
     GRANT SELECT ON librenms.* TO 'grafana_ro'@'10.1.10.52';
     FLUSH PRIVILEGES;
   "
   ```

2. **Update Grafana Datasource** with new read-only user

3. **Restrict Firewall:**
   ```bash
   ssh root@10.1.10.58
   sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.1.10.52" port port="3306" protocol="tcp" accept'
   sudo firewall-cmd --reload
   ```

4. **Consider SSL/TLS** for MySQL connection in production

---

## Dashboard Recommendations

### Community Dashboards (Import via ID)

These may require modifications to work with MySQL datasource:

| ID | Name | Notes |
|----|------|-------|
| `15306` | LibreNMS All-In-One | May need query rewrites |
| `12633` | Network Device Traffic | Port bandwidth visualization |
| `Custom` | Create your own | Use SQL queries from this doc |

### Building Custom Dashboards

**Tips:**
- Use variables for device selection: `SELECT DISTINCT hostname FROM devices`
- Add time filters: `WHERE last_polled > UNIX_TIMESTAMP(NOW() - INTERVAL 1 HOUR)`
- Join tables for rich context
- Use `ROUND()` for cleaner metric displays

---

## Troubleshooting

### Connection Test from Grafana Server
```bash
timeout 2 bash -c "echo > /dev/tcp/10.1.10.58/3306" && echo "✅ Connected" || echo "❌ Failed"
```

### Query Test from CLI
```bash
# If mysql client installed on Grafana server
mysql -h 10.1.10.58 -u librenms -p6jNTtWSlSeoFZiXVyhQqywm7xkYV01PP librenms -e "SELECT COUNT(*) FROM devices;"
```

### Check LibreNMS is Polling
```bash
ssh root@10.1.10.58
podman exec librenms-db mysql -u librenms -p6jNTtWSlSeoFZiXVyhQqywm7xkYV01PP librenms -e "
  SELECT hostname, FROM_UNIXTIME(last_polled) as last_poll_time
  FROM devices
  WHERE disabled=0
  ORDER BY last_polled DESC
  LIMIT 5;
"
```

---

## Files Modified

1. **`/etc/containers/systemd/librenms-db.container`** (on LibreNMS server)
   - Added `PublishPort=3306:3306`

2. **`DATASOURCE_INTEGRATION_GUIDE.md`** (this repo)
   - Complete rewrite of LibreNMS section
   - Changed architecture from InfluxDB to MySQL
   - Added SQL query examples and table reference

3. **Grafana Datasources**
   - Deleted: `InfluxDB-LibreNMS` (ID 3)
   - Created: `LibreNMS-MySQL` (ID 6)

---

## Next Steps

### Immediate
- ✅ **Data is accessible** - you can query LibreNMS data now
- ✅ **Explore works** - test queries in Grafana Explore

### Optional Enhancements
1. Create custom dashboards for your specific devices
2. Implement read-only database user (security)
3. Set up firewall rules to restrict MySQL access
4. Enable MySQL SSL/TLS for encrypted connections
5. Create automated reports with scheduled queries

---

## Resources

- **Main Integration Guide:** `DATASOURCE_INTEGRATION_GUIDE.md`
- **LibreNMS Database Schema:** https://docs.librenms.org/Support/Database-Schema/
- **Grafana MySQL Datasource:** https://grafana.com/docs/grafana/latest/datasources/mysql/
- **SQL Reference:** https://dev.mysql.com/doc/refman/8.0/en/sql-syntax.html

---

**Status:** ✅ LibreNMS data fully accessible in Grafana via MySQL datasource
**17 devices** actively monitored and queryable
