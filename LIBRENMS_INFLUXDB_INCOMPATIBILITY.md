# LibreNMS → InfluxDB Integration Issue

**Date:** 2026-02-05
**Status:** ❌ Incompatible - LibreNMS PHP library doesn't support InfluxDB v2.x properly

---

## The Problem

LibreNMS has **devices configured and polling**, but **no data is reaching InfluxDB**.

### Root Cause

```
Poller_0-17(ERROR):Polling device 4 failed with exit code 1:
PHP Error(2): Undefined array key "results" from
vendor/influxdb/influxdb-php/src/InfluxDB/ResultSet.php:104
in /opt/librenms/LibreNMS/Data/Store/InfluxDB.php:56
```

**Explanation:**
- LibreNMS uses the `influxdb/influxdb-php` library designed for **InfluxDB v1.x**
- We are running **InfluxDB v2.7.12**
- InfluxDB v2's API returns responses in a different format
- Even with v1 compatibility layer enabled, LibreNMS's PHP code fails when checking if the database exists

---

## What Was Tried

### ✅ Attempt 1: v2 Native Configuration
- **Result:** Failed - PHP library doesn't understand v2 responses

### ✅ Attempt 2: v1 Compatibility Layer
- Created DBRP mapping: `librenms` database → `librenms` bucket
- Changed config to use `version = 1`
- **Result:** Still failed - PHP library still can't parse responses

### ❌ Attempt 3: UDP Transport (not viable)
- UDP bypasses database existence check
- **Problem:** InfluxDB v2 doesn't have UDP enabled by default (v1-only feature)

---

## Solution Options

### Option 1: Downgrade to InfluxDB v1.8 ⚠️ (Not Recommended)

**Pros:**
- Native LibreNMS compatibility
- Simpler setup

**Cons:**
- InfluxDB v1.8 is EOL (End of Life)
- Missing v2 features (Flux query language, better UI)
- Would break existing InfluxDB-LibreNMS datasource in Grafana

---

### Option 2: Use Telegraf as Middleware 🎯 (Recommended)

**Architecture:**
```
LibreNMS → Prometheus Exporter → Telegraf → InfluxDB v2 → Grafana
```

**How it works:**
1. LibreNMS exports metrics via **Prometheus exporter** (built-in)
2. **Telegraf** scrapes Prometheus endpoint
3. Telegraf writes to InfluxDB v2 (native support)
4. Grafana queries InfluxDB

**Pros:**
- ✅ Works with InfluxDB v2
- ✅ No PHP compatibility issues
- ✅ More flexible metric transformation

**Cons:**
- Requires Telegraf deployment
- Additional component to manage

---

### Option 3: LibreNMS → Prometheus → Remote Write → InfluxDB

**Architecture:**
```
LibreNMS → Prometheus → (remote_write) → InfluxDB v2 → Grafana
```

**How it works:**
1. LibreNMS exports to **Prometheus** (built-in exporter)
2. Prometheus remote-writes to InfluxDB v2
3. Grafana queries InfluxDB

**Pros:**
- ✅ Prometheus provides time-series aggregation
- ✅ Can query either Prometheus OR InfluxDB in Grafana

**Cons:**
- Requires Prometheus deployment
- Remote-write adds latency

---

### Option 4: Query LibreNMS MySQL Directly from Grafana ⚡ (Simplest)

**Architecture:**
```
LibreNMS MySQL ← (SQL) ← Grafana
```

**How it works:**
- LibreNMS stores all metrics in its MariaDB database
- Add MySQL datasource to Grafana
- Query LibreNMS tables directly

**Pros:**
- ✅ No integration needed - data is already there
- ✅ Works immediately
- ✅ No additional components

**Cons:**
- SQL queries are more complex than Flux
- Not a true time-series database
- May impact LibreNMS performance if queries are heavy

---

## Recommendation

**For immediate data visibility:** Use **Option 4** (MySQL datasource)
**For production long-term:** Use **Option 2** (Telegraf middleware)

---

## Current Status

- ❌ InfluxDB integration: **Disabled** (was causing polling errors)
- ✅ LibreNMS: **Polling devices normally**
- ✅ Zabbix → Grafana: **Working**
- ⏸️ LibreNMS → InfluxDB → Grafana: **On hold pending solution**

---

## Next Steps (Your Choice)

### If you want MySQL datasource (quickest):
```bash
# Add MySQL datasource to Grafana
# Host: 10.1.10.58:3306
# Database: librenms
# User: librenms
# Password: (from LibreNMS .env)
```

### If you want Telegraf solution:
1. Deploy Telegraf container
2. Configure LibreNMS Prometheus exporter
3. Configure Telegraf to scrape and write to InfluxDB
4. Update Grafana dashboards

---

## Files Modified

- `/opt/librenms/data/config/influxdb.php` - **REMOVED** (was causing errors)
- `LIBRENMS_INFLUXDB_SETUP_COMPLETE.md` - Previous (now obsolete)

---

## Technical Details

### InfluxDB v1 Compatibility Layer Created
```bash
# DBRP mapping exists but LibreNMS can't use it
influx v1 dbrp list
# ID: 10378b4ea5210000
# Database: librenms
# Bucket: librenms (386e95072bd48296)
# RP: autogen
```

### Error Source
`/opt/librenms/LibreNMS/Data/Store/InfluxDB.php:56`
- Calls: `$this->connection->exists()`
- InfluxDB PHP library expects v1 JSON response with "results" key
- InfluxDB v2 returns different JSON structure
- No workaround available without modifying LibreNMS source code

---

## References

- [LibreNMS InfluxDB Docs](https://docs.librenms.org/Extensions/metrics/#influxdb)
- [InfluxDB v1/v2 Compatibility](https://docs.influxdata.com/influxdb/v2.7/reference/api/influxdb-1x/)
- [Telegraf InfluxDB Output](https://github.com/influxdata/telegraf/tree/master/plugins/outputs/influxdb_v2)
