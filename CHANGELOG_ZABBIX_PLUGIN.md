# Grafana Zabbix Plugin Configuration - Changelog

## Summary

Added dedicated configuration section for Grafana Zabbix plugin with three new environment variables
that provide fine-grained control over plugin installation and performance tuning.

---

## New Environment Variables

### 1. `GRAFANA_INSTALL_ZABBIX_PLUGIN`

- **Purpose:** Enable/disable automatic Zabbix plugin installation
- **Type:** Boolean
- **Default:** `true`
- **Values:** `true` or `false`
- **Location:** `.env.example`

### 2. `GRAFANA_ZABBIX_PLUGIN_ID`

- **Purpose:** Specify Zabbix plugin ID from Grafana plugin registry
- **Type:** String
- **Default:** `alexanderzobnin-zabbix-app`
- **Location:** `.env.example`
- **Link:** <https://grafana.com/grafana/plugins/alexanderzobnin-zabbix-app/>

### 3. `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS`

- **Purpose:** Configure when to switch from history to trends table
- **Type:** Integer
- **Default:** `7` days
- **Range:** `1-365` days
- **Location:** `.env.example`
- **Impact:** Performance vs. detail trade-off

---

## Files Modified

### 1. `.env.example`

**Change:** Added new dedicated section "Grafana Zabbix Plugin (required)"

```bash
# ===================================================================
# Grafana Zabbix Plugin (required)
# ===================================================================
GRAFANA_INSTALL_ZABBIX_PLUGIN=true
GRAFANA_ZABBIX_PLUGIN_ID=alexanderzobnin-zabbix-app
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS=7
```

**Impact:** Users can now control plugin installation and performance tuning from one central location.

---

### 2. `quadlets/grafana.container`

**Change:** Added environment variables for plugin configuration

**Added lines:**

```ini
Environment=GRAFANA_INSTALL_ZABBIX_PLUGIN=%GRAFANA_INSTALL_ZABBIX_PLUGIN%
Environment=ZABBIX_TRENDS_THRESHOLD_DAYS=%GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS%
```

**Impact:** Grafana container receives plugin configuration via environment variables.

---

### 3. `configs/grafana/provisioning/datasources/datasources.yaml`

**Change:** Made trends threshold dynamic instead of hardcoded

**Before:**

```yaml
trendsFrom: "7d"
trendsRange: "7d"
```

**After:**

```yaml
trendsFrom: "${ZABBIX_TRENDS_THRESHOLD_DAYS}d"
trendsRange: "${ZABBIX_TRENDS_THRESHOLD_DAYS}d"
```

**Impact:** Trends threshold now configurable per deployment needs.

---

### 4. `scripts/install.sh`

**Change:** Added conditional plugin installation logic

**New functionality in `load_environment()`:**

```bash
# Set defaults for optional Grafana Zabbix plugin variables
GRAFANA_INSTALL_ZABBIX_PLUGIN="${GRAFANA_INSTALL_ZABBIX_PLUGIN:-true}"
GRAFANA_ZABBIX_PLUGIN_ID="${GRAFANA_ZABBIX_PLUGIN_ID:-alexanderzobnin-zabbix-app}"
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS="${GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS:-7}"
```

**New functionality in `install_quadlets()`:**

```bash
# Special handling for grafana.container to conditionally install plugin
if [[ "${filename}" == "grafana.container" ]]; then
    if [[ "${GRAFANA_INSTALL_ZABBIX_PLUGIN:-true}" == "true" && \
          -n "${GRAFANA_ZABBIX_PLUGIN_ID:-}" ]]; then
        # Replace the GF_INSTALL_PLUGINS line with the plugin ID
        sed -i "s|^Environment=GF_INSTALL_PLUGINS=.*|\
Environment=GF_INSTALL_PLUGINS=${GRAFANA_ZABBIX_PLUGIN_ID}|" \
          "${dest_file}"
        log_info "Enabled Zabbix plugin installation: ${GRAFANA_ZABBIX_PLUGIN_ID}"
    else
        # Remove the GF_INSTALL_PLUGINS line if plugin installation is disabled
        sed -i '/^Environment=GF_INSTALL_PLUGINS=/d' "${dest_file}"
        log_info "Zabbix plugin installation disabled"
    fi
fi
```

**Impact:**

- Plugin installation can be disabled by setting `GRAFANA_INSTALL_ZABBIX_PLUGIN=false`
- Defaults ensure backward compatibility if variables are not set
- Clear logging of plugin installation status

---

### 5. `VARIABLES_REFERENCE.md`

**Change:** Added comprehensive documentation for new variables

**Added sections:**

- Variable definitions table
- Grafana Zabbix Plugin Configuration section
- Trends threshold performance comparison table
- Configuration recommendations
- Usage examples

**Impact:** Complete reference documentation for all configuration options.

---

## Use Cases

### Standard Deployment (Recommended)

```bash
GRAFANA_INSTALL_ZABBIX_PLUGIN=true
GRAFANA_ZABBIX_PLUGIN_ID=alexanderzobnin-zabbix-app
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS=7
```

- **Scenario:** ~200 devices, 1-year retention
- **Performance:** Balanced speed and detail
- **Best for:** Most deployments

### Large Deployment (Performance Optimized)

```bash
GRAFANA_INSTALL_ZABBIX_PLUGIN=true
GRAFANA_ZABBIX_PLUGIN_ID=alexanderzobnin-zabbix-app
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS=3
```

- **Scenario:** 500+ devices, heavy query load
- **Performance:** Faster queries, less detail in historical data
- **Best for:** High-traffic environments

### Small Deployment (Detail Optimized)

```bash
GRAFANA_INSTALL_ZABBIX_PLUGIN=true
GRAFANA_ZABBIX_PLUGIN_ID=alexanderzobnin-zabbix-app
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS=14
```

- **Scenario:** < 100 devices, infrequent queries
- **Performance:** More detailed history, slower queries
- **Best for:** Small environments with occasional deep analysis

### Disable Zabbix Integration

```bash
GRAFANA_INSTALL_ZABBIX_PLUGIN=false
```

- **Scenario:** Testing, custom plugin setup, no Zabbix integration
- **Impact:** Skips plugin installation entirely

---

## Performance Impact

### Trends Threshold Comparison

| Threshold | Query Speed | Detail Level | Trends DB Size | Use Case |
|-----------|-------------|--------------|----------------|----------|
| 1 day | ⚡⚡⚡ Fastest | ⭐ Basic | 📦 Smallest | 1000+ hosts |
| 3 days | ⚡⚡ Fast | ⭐⭐ Good | 📦📦 Small | 500-1000 hosts |
| **7 days** | ⚡ Balanced | ⭐⭐⭐ Very Good | 📦📦📦 Medium | **< 500 hosts** |
| 14 days | 🐢 Slow | ⭐⭐⭐⭐ Excellent | 📦📦📦📦 Large | < 100 hosts |
| 30 days | 🐢🐢 Slower | ⭐⭐⭐⭐⭐ Maximum | 📦📦📦📦📦 Very Large | Special cases |

---

## Backward Compatibility

All changes are **fully backward compatible**:

1. ✅ If variables are not set, defaults are applied automatically
2. ✅ Default behavior matches previous hardcoded values
3. ✅ Existing installations continue to work without changes
4. ✅ New installations get the benefits of flexible configuration

---

## Migration Guide

### For Existing Deployments

1. **No action required** - defaults match previous behavior
2. **Optional:** Add variables to existing `.env` for future flexibility
3. **Optional:** Tune `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` based on deployment size

### For New Deployments

1. Copy `.env.example` to `.env`
2. Configure all required variables (including Zabbix plugin settings)
3. Adjust `GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS` based on:
   - Number of monitored devices
   - Query frequency and patterns
   - Performance requirements

---

## Testing

### Verify Plugin Installation

```bash
# After deployment, check if plugin is installed
podman exec grafana grafana-cli plugins ls

# Expected output (if enabled):
# installed plugins:
# alexanderzobnin-zabbix-app @ x.x.x
```

### Verify Trends Threshold

```bash
# Check datasource configuration
podman exec grafana cat \
  /etc/grafana/provisioning/datasources/datasources.yaml | grep -A2 trends

# Expected output:
#   trendsFrom: "7d"
#   trendsRange: "7d"
```

### Test Plugin Disable

```bash
# Set GRAFANA_INSTALL_ZABBIX_PLUGIN=false in .env
# Run install script
sudo ./scripts/install.sh

# Verify plugin line is removed
grep GF_INSTALL_PLUGINS /etc/containers/systemd/grafana.container

# Should return nothing if disabled correctly
```

---

## Benefits

### 1. Flexibility

- ✅ Enable/disable plugin installation without editing Quadlet files
- ✅ Change plugin ID for testing or alternatives
- ✅ Tune performance per deployment needs

### 2. Performance Optimization

- ✅ Adjust trends threshold based on deployment size
- ✅ Balance query speed vs. historical detail
- ✅ Optimize for specific workloads

### 3. Better DevOps

- ✅ All configuration in one `.env` file
- ✅ Environment-specific tuning (dev/staging/prod)
- ✅ Clear documentation and examples

### 4. Maintainability

- ✅ No need to edit Quadlet files
- ✅ Centralized configuration management
- ✅ Easy to version control (via `.env.example`)

---

## Documentation Updates

Updated files:

- ✅ `.env.example` - New section with detailed comments
- ✅ `VARIABLES_REFERENCE.md` - Complete variable documentation
- ✅ `CHANGELOG_ZABBIX_PLUGIN.md` - This file

---

## Date

**Created:** 2026-01-28
**Version:** 1.1.0
**Impact:** Medium (new features, backward compatible)

---

## Related Issues/Requirements

- ✅ Requirements from `template/docs/requirements.md` - Zabbix integration with 7-day trends threshold
- ✅ Security standards from `template/docs/ai/CONTEXT.md` - No secrets in git, centralized config
- ✅ User request - Separate section for Grafana Zabbix plugin configuration

---

**Status:** ✅ Complete and Ready for Deployment
