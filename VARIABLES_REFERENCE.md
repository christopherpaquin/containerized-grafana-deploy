# Environment Variables Reference

This document lists all environment variables used in the Observability Stack deployment.

## ✅ Variable Coverage Status

All variables referenced in configuration files are defined in `.env.example`.

**Total Variables:** 16 required + 6 optional = 22 total

---

## 📋 Complete Variable List

### InfluxDB Variables

| Variable | Used In | Purpose | Example |
|----------|---------|---------|---------|
| `INFLUXDB_URL` | Docs, LibreNMS config | External URL for InfluxDB access | `http://grafana.example.com:8086` |
| `INFLUXDB_PORT` | Documentation, firewall config | InfluxDB HTTP port | `8086` |
| `INFLUXDB_ADMIN_USER` | influxdb.container | Initial admin username | `admin` |
| `INFLUXDB_ADMIN_PASSWORD` | influxdb.container | Initial admin password | `changeme_influxdb_password` |
| `INFLUXDB_ORG` | influxdb.container, grafana.container, datasources.yaml | Organization name | `observability` |
| `INFLUXDB_BUCKET` | influxdb.container, grafana.container, datasources.yaml | Bucket name for LibreNMS | `librenms` |
| `INFLUXDB_TOKEN` | influxdb, grafana, datasources | Admin API token | Generated: `openssl rand -base64 32` |

### Grafana Variables

| Variable | Used In | Purpose | Example |
|----------|---------|---------|---------|
| `GRAFANA_ADMIN_USER` | grafana.container | Grafana admin username | `admin` |
| `GRAFANA_ADMIN_PASSWORD` | grafana.container | Grafana admin password | `changeme_grafana_password` |
| `GRAFANA_DOMAIN` | grafana.container | Grafana server domain | `localhost` or `grafana.example.com` |

### Grafana Zabbix Plugin Variables

| Variable | Used In | Purpose | Example |
|----------|---------|---------|---------|
| `GRAFANA_INSTALL_ZABBIX_PLUGIN` | grafana, install.sh | Enable/disable Zabbix plugin install | `true` or `false` |
| `GRAFANA_ZABBIX_PLUGIN_ID` | grafana.container | Zabbix plugin ID to install | `alexanderzobnin-zabbix-app` |
| `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` | grafana.container, datasources.yaml | Days before using trends table | `7` |

### Zabbix Variables

| Variable | Used In | Purpose | Example |
|----------|---------|---------|---------|
| `ZABBIX_URL` | grafana.container, datasources | Zabbix API endpoint URL | `http://zabbix.example.com/api_jsonrpc.php` |
| `ZABBIX_API_TOKEN` | grafana.container, datasources.yaml | Zabbix API token (required) | Generated in Zabbix UI |

### Deprecated Zabbix Variables

| Variable | Status | Replacement |
|----------|--------|-------------|
| `ZABBIX_USER` | ❌ DEPRECATED | Use `ZABBIX_API_TOKEN` |
| `ZABBIX_PASSWORD` | ❌ DEPRECATED | Use `ZABBIX_API_TOKEN` |

**Note:** The Grafana Zabbix plugin requires API token authentication.
Username/password authentication is not supported.

### Optional Variables (Commented Out)

| Variable | Used In | Purpose | Example |
|----------|---------|---------|---------|
| `ZABBIX_DB_HOST` | datasources.yaml | Direct DB host (optional) | `zabbix-db.example.com` |
| `ZABBIX_DB_NAME` | datasources.yaml | Zabbix database name | `zabbix` |
| `ZABBIX_DB_USER` | datasources.yaml | DB username | `grafana_reader` |
| `ZABBIX_DB_PASSWORD` | datasources.yaml | DB password | `changeme_zabbix_db_password` |
| `LIBRENMS_DB_HOST` | - | LibreNMS DB host (optional) | `librenms.example.com` |
| `LIBRENMS_DB_NAME` | - | LibreNMS database name | `librenms` |
| `LIBRENMS_DB_USER` | - | DB username | `grafana_reader` |
| `LIBRENMS_DB_PASSWORD` | - | DB password | `changeme_librenms_db_password` |

---

## 🔄 Variable Substitution Flow

```text
.env file
    ↓
Source by install.sh
    ↓
envsubst in install_quadlets() function
    ↓
Variables replaced in Quadlet files: %VARIABLE% → actual value
    ↓
Quadlet files copied to /etc/containers/systemd/
    ↓
systemd reads Quadlet files
    ↓
Containers start with environment variables set
```

---

## 📝 Variable Usage by File

### Quadlet Files

**influxdb.container:**

```ini
Environment=DOCKER_INFLUXDB_INIT_USERNAME=%INFLUXDB_ADMIN_USER%
Environment=DOCKER_INFLUXDB_INIT_PASSWORD=%INFLUXDB_ADMIN_PASSWORD%
Environment=DOCKER_INFLUXDB_INIT_ORG=%INFLUXDB_ORG%
Environment=DOCKER_INFLUXDB_INIT_BUCKET=%INFLUXDB_BUCKET%
Environment=DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=%INFLUXDB_TOKEN%
```

**grafana.container:**

```ini
Environment=GF_INSTALL_PLUGINS=%GRAFANA_ZABBIX_PLUGIN_ID%
Environment=GF_SERVER_DOMAIN=%GRAFANA_DOMAIN%
Environment=GF_SECURITY_ADMIN_USER=%GRAFANA_ADMIN_USER%
Environment=GF_SECURITY_ADMIN_PASSWORD=%GRAFANA_ADMIN_PASSWORD%
Environment=INFLUXDB_ORG=%INFLUXDB_ORG%
Environment=INFLUXDB_BUCKET=%INFLUXDB_BUCKET%
Environment=INFLUXDB_TOKEN=%INFLUXDB_TOKEN%
Environment=ZABBIX_URL=%ZABBIX_URL%
Environment=ZABBIX_USER=%ZABBIX_USER%
Environment=ZABBIX_PASSWORD=%ZABBIX_PASSWORD%
```

### Configuration Files

**configs/grafana/provisioning/datasources/datasources.yaml:**

```yaml
# InfluxDB datasource
jsonData:
  organization: ${INFLUXDB_ORG}
  defaultBucket: ${INFLUXDB_BUCKET}
secureJsonData:
  token: ${INFLUXDB_TOKEN}

# Zabbix datasource
url: ${ZABBIX_URL}
jsonData:
  username: ${ZABBIX_USER}
secureJsonData:
  password: ${ZABBIX_PASSWORD}
```

---

## 🔒 Security Requirements

### Required Strong Passwords

These variables **MUST** be changed from defaults:

- ✅ `INFLUXDB_ADMIN_PASSWORD` - Minimum 16 characters
- ✅ `GRAFANA_ADMIN_PASSWORD` - Minimum 16 characters
- ✅ `ZABBIX_PASSWORD` - Minimum 16 characters
- ✅ `INFLUXDB_TOKEN` - Generate with: `openssl rand -base64 32`

### Optional Database Passwords

If enabling direct DB access:

- ⚠️ `ZABBIX_DB_PASSWORD` - Minimum 16 characters
- ⚠️ `LIBRENMS_DB_PASSWORD` - Minimum 16 characters

---

## 📝 InfluxDB Configuration for LibreNMS

### Understanding INFLUXDB_URL and INFLUXDB_PORT

These variables are used for **external access** to InfluxDB,
primarily for LibreNMS to push metrics.

**INFLUXDB_URL:**

- Full URL including protocol, hostname/IP, and port
- Used by LibreNMS to connect and push metrics
- Must be reachable from the LibreNMS VM
- Example: `http://grafana.example.com:8086`

**INFLUXDB_PORT:**

- The HTTP port InfluxDB listens on
- Default: `8086`
- Used for documentation and firewall configuration
- Internal container uses this port on the obs-net network

### Important Notes

1. **Hostname/IP:** Change `grafana.example.com` to your actual Grafana VM hostname or IP
2. **Network Access:** Ensure LibreNMS VM can reach this URL (firewall rules, routing)
3. **Internal vs External:**
   - **Internal:** Containers use `http://influxdb:8086` on obs-net network
   - **External:** LibreNMS uses `${INFLUXDB_URL}` from outside the container network

### LibreNMS Configuration Steps

1. **On Grafana VM** - Note the InfluxDB URL from `.env`:

   ```bash
   grep INFLUXDB_URL .env
   # Example: INFLUXDB_URL=http://10.0.1.100:8086
   ```

2. **On LibreNMS VM** - Configure InfluxDB export:

   - Navigate to: Settings → Plugins → InfluxDB
   - Enable: ✅ InfluxDB export
   - URL: `${INFLUXDB_URL}` (from your .env)
   - Organization: `observability` (from INFLUXDB_ORG)
   - Bucket: `librenms` (from INFLUXDB_BUCKET)
   - Token: Copy from `INFLUXDB_TOKEN` in .env
   - Test connection and save

3. **Verify connectivity:**

   ```bash
   # From LibreNMS VM, test connection
   curl http://grafana.example.com:8086/health

   # Expected output:
   # {"name":"influxdb","message":"ready for queries and writes","status":"pass"}
   ```

---

## 📝 Grafana Zabbix Plugin Configuration

### Understanding the Trends Threshold

The `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` variable controls when Zabbix switches from detailed
history to aggregated trends data.

**How it works:**

- Data **newer** than threshold → Query `history` table (detailed, raw values)
- Data **older** than threshold → Query `trends` table (hourly averages)

**Performance Impact:**

| Threshold | Query Speed | Detail Level | Trends Table Size |
|-----------|-------------|--------------|-------------------|
| 1 day | Fastest | Less detail for old data | Smallest |
| 7 days ⭐ | Balanced | Good detail for week | Recommended |
| 30 days | Slower | Best detail for month | Larger |
| 90 days | Slowest | Maximum detail | Very large |

**Recommendations:**

- **7 days** (default) - Best balance for 1-year retention
- **1-3 days** - For very large Zabbix deployments (1000+ hosts)
- **14-30 days** - For smaller deployments with high detail needs

### Disabling Zabbix Plugin Installation

To disable automatic Zabbix plugin installation:

```bash
# In .env file
GRAFANA_INSTALL_ZABBIX_PLUGIN=false
```

This is useful if:

- Using a custom Grafana image with pre-installed plugins
- Installing plugins manually after deployment
- Testing without Zabbix integration

---

## 🔧 Configuration Steps

1. **Copy template:**

   ```bash
   cp .env.example .env
   ```

2. **Generate secure token:**

   ```bash
   # Generate InfluxDB token
   openssl rand -base64 32

   # Or use this one-liner to update .env
   TOKEN=$(openssl rand -base64 32)
   sed -i "s/changeme_random_token_here_32chars_minimum/$TOKEN/" .env
   ```

3. **Set strong passwords:**

   ```bash
   # Generate passwords
   openssl rand -base64 24  # For admin passwords
   ```

4. **Configure external systems:**

   ```bash
   # Update Zabbix connection
   ZABBIX_URL=http://your-zabbix-server/api_jsonrpc.php
   ZABBIX_USER=your_api_user
   ZABBIX_PASSWORD=your_secure_password
   ```

5. **Secure the file:**

   ```bash
   chmod 600 .env
   chown root:root .env
   ```

6. **Verify all required variables are set:**

   ```bash
   # Check for placeholder values
   grep "changeme" .env

   # Should return nothing after configuration
   ```

---

## ✅ Validation

Before running `./scripts/install.sh`, verify:

- [ ] All `changeme_*` placeholders replaced
- [ ] `INFLUXDB_TOKEN` is at least 32 characters
- [ ] Passwords are at least 16 characters
- [ ] `ZABBIX_URL` points to your Zabbix API
- [ ] `GRAFANA_DOMAIN` set to your server's FQDN or IP
- [ ] File permissions set: `chmod 600 .env`

---

## 🐛 Troubleshooting

### Variable Not Substituted

**Symptom:** `%VARIABLE%` appears in container environment

**Cause:** Variable not defined in `.env` or not sourced by install script

**Solution:**

```bash
# Verify variable exists
grep "VARIABLE_NAME" .env

# Re-run install
sudo ./scripts/install.sh
```

### Environment Variable Not Applied

**Symptom:** Container behavior doesn't reflect configured value

**Cause:** Container needs restart after Quadlet file update

**Solution:**

```bash
systemctl daemon-reload
systemctl restart <service>.service
```

### Check Active Variables in Container

```bash
# View all environment variables in a container
podman exec grafana env | sort

# Check specific variable
podman exec grafana printenv GF_INSTALL_PLUGINS
```

---

## 📚 Related Documentation

- [.env.example](.env.example) - Environment template
- [README.md](README.md) - Main documentation
- [scripts/install.sh](scripts/install.sh) - Installation script
- [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - Deployment overview
