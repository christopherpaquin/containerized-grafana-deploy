# 📊 Performance Tuning and Scaling Guide

This document provides detailed guidance on tuning and scaling the Observability Stack for
optimal performance.

---

## 📋 Table of Contents

- [System Sizing](#system-sizing)
- [Component-Specific Tuning](#component-specific-tuning)
  - [Grafana](#grafana-tuning)
  - [InfluxDB](#influxdb-tuning)
  - [Prometheus](#prometheus-tuning)
  - [Loki](#loki-tuning)
  - [Alloy](#alloy-tuning)
- [Storage Optimization](#storage-optimization)
- [Network Optimization](#network-optimization)
- [Resource Limits](#resource-limits)
- [Monitoring the Monitors](#monitoring-the-monitors)
- [Troubleshooting Performance](#troubleshooting-performance)

---

## System Sizing

### Baseline Configuration

**Target:** ~200 devices, 1-year retention

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Grafana | 1 core | 2 GB | 10 GB |
| InfluxDB | 2 cores | 4 GB | 150 GB |
| Prometheus | 2 cores | 8 GB | 200 GB |
| Loki | 2 cores | 4 GB | 100 GB |
| Alloy | 1 core | 1 GB | 5 GB |
| **Total** | **8 cores** | **24 GB** | **500 GB** |

### Scaling Guidelines

#### Small Deployment (< 100 devices)

- 4 vCPU, 16 GB RAM, 250 GB SSD
- Retention: 6 months
- Prometheus: 4 GB RAM, 100 GB storage
- InfluxDB: 2 GB RAM, 75 GB storage

#### Medium Deployment (100-200 devices) ⭐ **Baseline**

- 8 vCPU, 24 GB RAM, 500 GB SSD
- Retention: 1 year
- Prometheus: 8 GB RAM, 200 GB storage
- InfluxDB: 4 GB RAM, 150 GB storage

#### Large Deployment (200-500 devices)

- 16 vCPU, 48 GB RAM, 1 TB SSD
- Retention: 1 year
- Prometheus: 16 GB RAM, 500 GB storage
- InfluxDB: 8 GB RAM, 300 GB storage
- Consider Prometheus federation

#### Very Large Deployment (> 500 devices)

- Consider multi-VM deployment
- Prometheus federation required
- InfluxDB clustering (enterprise)
- Loki distributed mode
- Separate Grafana from backends

---

## Component-Specific Tuning

### Grafana Tuning

#### Configuration File

Edit Quadlet file: `/etc/containers/systemd/grafana.container`

```ini
[Container]
# Increase memory for many dashboards/users
Memory=4G
MemorySwap=4G

# Environment variables for tuning
Environment=GF_DATABASE_MAX_OPEN_CONN=100
Environment=GF_DATABASE_MAX_IDLE_CONN=50
Environment=GF_DATABASE_CONN_MAX_LIFETIME=14400

# Query timeout for slow data sources
Environment=GF_DATAPROXY_TIMEOUT=300
Environment=GF_DATAPROXY_KEEP_ALIVE_SECONDS=300

# Rendering (for image rendering)
# Environment=GF_RENDERING_SERVER_URL=http://renderer:8081/render
# Environment=GF_RENDERING_CALLBACK_URL=http://grafana:3000/
```

#### Database Optimization

Grafana uses SQLite by default. For production, consider PostgreSQL:

```ini
Environment=GF_DATABASE_TYPE=postgres
Environment=GF_DATABASE_HOST=postgres:5432
Environment=GF_DATABASE_NAME=grafana
Environment=GF_DATABASE_USER=grafana
Environment=GF_DATABASE_PASSWORD=${GRAFANA_DB_PASSWORD}
Environment=GF_DATABASE_SSL_MODE=disable
```

#### Plugin Performance

```bash
# List installed plugins
podman exec grafana grafana-cli plugins ls

# Update plugins
podman exec grafana grafana-cli plugins update-all

# Remove unused plugins
podman exec grafana grafana-cli plugins remove <plugin-id>
```

#### Query Caching

Enable query caching for better performance:

```ini
Environment=GF_QUERY_CACHE_ENABLED=true
Environment=GF_QUERY_CACHE_TTL=300  # 5 minutes
```

---

### InfluxDB Tuning

#### Memory and CPU

Edit: `/etc/containers/systemd/influxdb.container`

```ini
[Container]
# InfluxDB is memory-intensive for large cardinality
Memory=8G
MemorySwap=8G
CPUQuota=200%  # 2 CPU cores
```

#### Storage Engine Configuration

Create `/srv/obs/influxdb/config/config.toml`:

```toml
[storage-cache-max-memory-size]
# Cache size - adjust based on available RAM
# Default: 1GB, Recommended: 25% of total RAM
cache-max-memory-size = "2147483648"  # 2 GB

[storage-cache-snapshot-memory-size]
# Snapshot size
cache-snapshot-memory-size = "26214400"  # 25 MB

[storage-cache-snapshot-write-cold-duration]
# How long to wait before flushing
cache-snapshot-write-cold-duration = "10m"

[storage-compact-full-write-cold-duration]
# Compaction trigger interval
compact-full-write-cold-duration = "4h"

[storage-max-concurrent-compactions]
# Number of simultaneous compactions
max-concurrent-compactions = 2

[storage-max-index-log-file-size]
# TSI index log file size before flush
max-index-log-file-size = "1048576"  # 1 MB

[query-concurrency]
# Max concurrent queries
query-concurrency = 10

[query-queue-size]
# Query queue depth
query-queue-size = 100
```

Mount config in Quadlet:

```ini
Volume=/srv/obs/influxdb/config/config.toml:/etc/influxdb2/config.toml:Z,ro
```

#### Cardinality Management

High cardinality kills InfluxDB performance.

```bash
# Check cardinality
podman exec influxdb influx query '
import "influxdata/influxdb/schema"
schema.tagValues(
  bucket: "librenms",
  tag: "host"
)
'

# Monitor cardinality
podman exec influxdb influx query '
import "influxdata/influxdb/schema"
schema.measurementCardinalityByBucket(bucket: "librenms")
'
```

**Best Practices:**

- Limit tags to < 100K unique combinations
- Use fields for high-cardinality data
- Configure LibreNMS to filter metrics

#### Retention Policies

```bash
# Check retention policy
podman exec influxdb influx bucket list

# Update retention (API)
curl -XPATCH "http://localhost:8086/api/v2/buckets/${BUCKET_ID}" \
  -H "Authorization: Token ${INFLUXDB_TOKEN}" \
  -H "Content-type: application/json" \
  -d '{
    "retentionRules": [
      {
        "type": "expire",
        "everySeconds": 31536000
      }
    ]
  }'
```

---

### Prometheus Tuning

#### Storage Retention

Edit: `/etc/containers/systemd/prometheus.container`

```ini
Exec=--config.file=/etc/prometheus/prometheus.yml \
     --storage.tsdb.path=/prometheus \
     --storage.tsdb.retention.time=365d \
     --storage.tsdb.retention.size=200GB \
     --storage.tsdb.min-block-duration=2h \
     --storage.tsdb.max-block-duration=2h \
     --web.enable-lifecycle \
     --web.enable-admin-api
```

#### Memory Configuration

```ini
[Container]
Memory=16G
MemorySwap=16G
CPUQuota=400%  # 4 cores
```

**Memory Estimation:**

- 1-3 bytes per sample in RAM
- 1-2 bytes per sample on disk
- Formula: `memory = active_series * scrape_interval * retention_seconds * 2 bytes / (3600 * 24)`

Example for 100K series, 15s interval, 365d retention:

```text
100000 * (1/15) * (365*24*3600) * 2 / (365*24*3600) = ~13 GB
```

#### Scrape Configuration Optimization

Edit: `/srv/obs/prometheus/config/prometheus.yml`

```yaml
global:
  scrape_interval: 30s     # Increase for less CPU/storage
  scrape_timeout: 10s
  evaluation_interval: 30s

  # External labels for federation
  external_labels:
    cluster: 'grafana-vm'
    environment: 'production'

# Relabeling to drop metrics
scrape_configs:
  - job_name: 'node-exporter'
    metric_relabel_configs:
      # Drop high-cardinality metrics
      - source_labels: [__name__]
        regex: 'node_network_.*'
        action: drop

      # Keep only specific metrics
      - source_labels: [__name__]
        regex: 'node_(cpu|memory|disk|filesystem)_.*'
        action: keep
```

#### Compaction

Prometheus automatically compacts data. Monitor compaction:

```bash
# View compaction status
podman exec prometheus promtool tsdb analyze /prometheus
```

#### Query Performance

**Use recording rules** for expensive queries:

Create `/srv/obs/prometheus/config/rules/aggregate.yml`:

```yaml
groups:
  - name: aggregate_metrics
    interval: 60s
    rules:
      # Pre-aggregate CPU usage
      - record: instance:node_cpu_utilization:ratio
        expr: |
          avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

      # Pre-aggregate memory usage
      - record: instance:node_memory_utilization:ratio
        expr: |
          (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
```

Update `prometheus.yml`:

```yaml
rule_files:
  - "/etc/prometheus/rules/*.yml"
```

Reload:

```bash
systemctl restart prometheus.service
```

#### Remote Storage (Optional)

For long-term storage beyond 1 year:

```yaml
remote_write:
  - url: "http://thanos-receive:19291/api/v1/receive"
    queue_config:
      capacity: 10000
      max_shards: 50
      max_samples_per_send: 5000
      batch_send_deadline: 5s
```

---

### Loki Tuning

#### Retention and Compaction

Edit: `/srv/obs/loki/config/loki.yaml`

```yaml
limits_config:
  # Retention
  retention_period: 8760h  # 1 year

  # Ingestion limits (adjust for log volume)
  ingestion_rate_mb: 20          # MB/s per stream
  ingestion_burst_size_mb: 40    # Burst size

  # Query limits
  max_query_length: 8760h
  max_query_lookback: 8760h
  max_query_series: 1000
  max_streams_per_user: 10000
  max_global_streams_per_user: 50000

  # Per-query limits
  max_entries_limit_per_query: 10000
  max_cache_freshness_per_query: 10m

compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

#### Container Resources

```ini
[Container]
Memory=8G
MemorySwap=8G
CPUQuota=400%  # 4 cores
```

#### Query Performance Best Practices

**Use label filters early:**

❌ Bad (slow):

```logql
{job="alloy"} |= "error"
```

✅ Good (fast):

```logql
{job="alloy", unit="grafana.service"} |= "error"
```

**Avoid regex when possible:**

❌ Bad:

```logql
{job="alloy"} |~ "error|ERROR|Error"
```

✅ Good:

```logql
{job="alloy"} |~ "(?i)error"
```

#### Chunk Caching

For better query performance, enable caching:

```yaml
chunk_store_config:
  max_look_back_period: 8760h  # 1 year

query_range:
  align_queries_with_step: true
  max_retries: 5
  cache_results: true
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 500
        ttl: 24h
```

---

### Alloy Tuning

#### Resource Configuration

```ini
[Container]
Memory=2G
MemorySwap=2G
CPUQuota=100%  # 1 core
```

#### Log Collection Rate

Edit: `/srv/obs/alloy/config/config.alloy`

```hcl
loki.source.journal "systemd" {
  path          = "/var/log/journal"
  max_age       = "12h"  # Reduce for less backfill

  forward_to = [
    loki.write.local.receiver,
  ]
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"

    // Batch configuration
    batch_size  = 1048576  // 1MB (increase for efficiency)
    batch_wait  = "5s"     // Wait longer to accumulate

    // Backpressure
    min_backoff_period = "1s"
    max_backoff_period = "10m"
    max_backoff_retries = 10
  }

  // External labels
  external_labels = {
    cluster = "grafana-vm",
    env     = "production",
  }
}
```

#### Filtering Logs

Reduce ingestion by filtering:

```hcl
loki.source.journal "systemd" {
  path    = "/var/log/journal"
  max_age = "12h"

  // Only collect from specific units
  matches = [
    "_SYSTEMD_UNIT=grafana.service",
    "_SYSTEMD_UNIT=prometheus.service",
    "_SYSTEMD_UNIT=loki.service",
  ]

  forward_to = [
    loki.process.filter.receiver,
  ]
}

loki.process "filter" {
  // Drop debug logs
  stage.match {
    selector = "{unit=~\".+\"}"

    stage.regex {
      expression = "(?P<level>DEBUG|TRACE)"
    }

    stage.drop {
      source = "level"
    }
  }

  forward_to = [
    loki.write.local.receiver,
  ]
}
```

---

## Storage Optimization

### Filesystem Recommendations

**Best Performance:**

- XFS (recommended for RHEL)
- ext4 (good alternative)
- Avoid NFS for databases

**Mount Options:**

```bash
# /etc/fstab
UUID=xxx /srv xfs defaults,noatime,nodiratime 0 2
```

Benefits of `noatime`:

- Reduces write IOPS by 30-50%
- No access time updates
- Safe for monitoring workloads

### Directory Layout

```text
/srv/obs/          # Data partition (500GB+)
├── grafana/       # Small (~10GB)
├── influxdb/      # Large (~150GB)
├── prometheus/    # Large (~200GB)
├── loki/          # Medium (~100GB)
└── alloy/         # Small (~5GB)
```

### Monitoring Disk Usage

```bash
# Check usage by component
du -sh /srv/obs/*

# Watch in real-time
watch -n 60 "df -h /srv && du -sh /srv/obs/*"

# Alert when > 80% full
```

### Disk Space Alerts

Create monitoring script: `/usr/local/bin/check-obs-disk.sh`

```bash
#!/bin/bash
THRESHOLD=80
USAGE=$(df -h /srv/obs | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "WARNING: /srv/obs is ${USAGE}% full (threshold: ${THRESHOLD}%)"
    # Send alert (email, webhook, etc.)
fi
```

Cron job:

```bash
# /etc/cron.hourly/check-obs-disk
0 * * * * /usr/local/bin/check-obs-disk.sh
```

---

## Network Optimization

### Podman Network Configuration

Default bridge network is sufficient for most deployments.

For better performance:

```bash
# Increase MTU (if supported)
podman network rm obs-net
podman network create obs-net --driver bridge --opt mtu=9000
```

### Firewall Tuning

```bash
# Increase conntrack limits
echo "net.netfilter.nf_conntrack_max = 262144" >> /etc/sysctl.conf
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 86400" >> /etc/sysctl.conf
sysctl -p
```

### DNS Resolution

Use local DNS or `/etc/hosts` for container names:

```bash
# /etc/hosts (on host)
127.0.0.1 grafana prometheus loki influxdb alloy
```

---

## Resource Limits

### CPU Quotas

Set CPU limits in Quadlet files:

```ini
[Container]
# 200% = 2 full CPU cores
CPUQuota=200%

# CPU shares (relative weight)
CPUShares=1024
```

### Memory Limits

```ini
[Container]
# Hard limit
Memory=8G

# Swap limit (should equal Memory)
MemorySwap=8G

# Soft limit (allows bursting)
MemoryReservation=6G

# OOM behavior
OOMScoreAdjust=500
```

### I/O Limits

```ini
[Container]
# Read IOPS limit
IOReadIOPSMax=1000

# Write IOPS limit
IOWriteIOPSMax=500

# Bandwidth limit (bytes/sec)
IOReadBandwidthMax=100M
IOWriteBandwidthMax=50M
```

---

## Monitoring the Monitors

### Self-Monitoring Dashboard

Create Grafana dashboard to monitor the observability stack itself:

**Metrics to track:**

- Container CPU/memory usage (via Podman stats)
- Disk usage per component
- Query latency (Prometheus, Loki, InfluxDB)
- Ingestion rate (logs/sec, metrics/sec)
- Error rates from container logs

### Prometheus Self-Scrape

Already configured in baseline `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

### Health Check Automation

Run health check on cron:

```bash
# /etc/cron.d/obs-health-check
*/15 * * * * root \
  /root/containerized-grafana-deploy/scripts/health-check.sh \
  > /var/log/obs-health.log 2>&1
```

---

## Troubleshooting Performance

### High CPU Usage

**Identify culprit:**

```bash
# Container stats
podman stats

# Process inside container
podman top <container-name>

# System-wide
top -H
```

**Common causes:**

- Prometheus: Too many active series or high scrape frequency
- Loki: Complex regex queries
- InfluxDB: High cardinality
- Grafana: Too many concurrent dashboard refreshes

### High Memory Usage

**Check memory:**

```bash
# Container memory
podman stats

# OOM kills
journalctl -k | grep -i oom
```

**Solutions:**

- Increase memory limits in Quadlet files
- Reduce retention periods
- Lower scrape frequencies
- Optimize queries

### Slow Queries

**Prometheus:**

```bash
# Query analysis
curl http://localhost:9090/api/v1/status/tsdb

# Top queries
curl http://localhost:9090/api/v1/status/runtimeinfo
```

**Loki:**

```bash
# Query metrics
curl http://localhost:3100/metrics | grep query_duration
```

**InfluxDB:**

```bash
# Query log
podman logs influxdb 2>&1 | grep "query"
```

### Disk I/O Bottlenecks

**Identify I/O wait:**

```bash
iostat -x 1

# Check IOPS
iostat -xd 1 /dev/sda
```

**Solutions:**

- Move to SSD
- Separate data onto multiple disks
- Tune compaction intervals
- Reduce retention

---

## Performance Checklist

Use this checklist to verify optimal configuration:

### System Level

- [ ] XFS or ext4 with `noatime`
- [ ] SSD for `/srv/obs`
- [ ] Sufficient RAM (24 GB minimum)
- [ ] SELinux labels applied correctly
- [ ] Firewall optimized (conntrack limits)

### Component Level

- [ ] Prometheus: Memory sized for cardinality
- [ ] Prometheus: Recording rules for expensive queries
- [ ] InfluxDB: Cardinality < 100K
- [ ] InfluxDB: Cache size = 25% of RAM
- [ ] Loki: Compaction enabled
- [ ] Loki: Query filters optimized
- [ ] Grafana: Query cache enabled
- [ ] Alloy: Batch size optimized

### Monitoring

- [ ] Self-monitoring dashboard created
- [ ] Disk usage alerts configured
- [ ] Health check automated (cron)
- [ ] Resource limits set for all containers

---

**For additional help, see main [README.md](../README.md) or open an issue.**
