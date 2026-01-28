# Zabbix API Token Authentication Migration

## 📋 Overview

This document describes the migration from username/password authentication to API token authentication
for Zabbix integration in Grafana.

---

## 🔄 What Changed

### Authentication Method

| Aspect | Before (Username/Password) | After (API Token) |
|--------|---------------------------|-------------------|
| **Authentication** | Username + Password | API Token |
| **Security** | Password stored in env | Token stored in env |
| **Variables** | `ZABBIX_USER`, `ZABBIX_PASSWORD` | `ZABBIX_API_TOKEN` |
| **Rotation** | Requires password change | Token revocation |
| **Audit Trail** | User-level | Token-level |
| **Support** | ❌ Not supported by plugin | ✅ Required by plugin |

---

## 📝 Variable Changes

### Removed Variables

```bash
# DEPRECATED - Do not use
ZABBIX_USER=grafana
ZABBIX_PASSWORD=changeme_password
```

### New Variables

```bash
# REQUIRED - Use API token authentication
ZABBIX_API_TOKEN=changeme_zabbix_api_token
```

### Unchanged Variables

```bash
# Still required
ZABBIX_URL=http://zabbix.example.com/api_jsonrpc.php
GRAFANA_ZABBIX_TRENDS_THRESHOLD_DAYS=7
```

---

## 🔧 Configuration Changes

### .env.example

**Before:**

```bash
# Zabbix Integration
ZABBIX_URL=http://zabbix.example.com/api_jsonrpc.php
ZABBIX_USER=grafana
ZABBIX_PASSWORD=changeme_zabbix_password
```

**After:**

```bash
# Zabbix Integration (API Token Authentication)
ZABBIX_URL=http://zabbix.example.com/api_jsonrpc.php

# Zabbix API Token (REQUIRED)
# API token authentication is the only supported method
# To generate: Administration → Users → API tokens → Create
ZABBIX_API_TOKEN=changeme_zabbix_api_token

# DEPRECATED: Username/password authentication (DO NOT USE)
# ZABBIX_USER=grafana              # DEPRECATED
# ZABBIX_PASSWORD=changeme_password # DEPRECATED
```

### datasources.yaml

**Before:**

```yaml
jsonData:
  username: ${ZABBIX_USER}
  trends: true
  trendsFrom: "7d"
secureJsonData:
  password: ${ZABBIX_PASSWORD}
```

**After:**

```yaml
jsonData:
  trends: true
  trendsFrom: "${ZABBIX_TRENDS_THRESHOLD_DAYS}d"
secureJsonData:
  apiToken: ${ZABBIX_API_TOKEN}
```

### grafana.container (Quadlet)

**Before:**

```ini
Environment=ZABBIX_USER=%ZABBIX_USER%
Environment=ZABBIX_PASSWORD=%ZABBIX_PASSWORD%
```

**After:**

```ini
Environment=ZABBIX_API_TOKEN=%ZABBIX_API_TOKEN%
```

---

## 🚀 Migration Steps

### For New Deployments

1. **Generate API Token in Zabbix:**
   - Administration → Users → Select user → API tokens
   - Click "Create API token"
   - Description: "Grafana Integration"
   - Click "Add" and copy token

2. **Configure .env:**

   ```bash
   cp .env.example .env
   vi .env
   # Set: ZABBIX_API_TOKEN=<your-generated-token>
   ```

3. **Deploy:**

   ```bash
   sudo ./scripts/install.sh
   ```

### For Existing Deployments

1. **Generate API Token in Zabbix** (see above)

2. **Update .env:**

   ```bash
   # Remove old variables
   sed -i '/^ZABBIX_USER=/d' .env
   sed -i '/^ZABBIX_PASSWORD=/d' .env

   # Add new variable
   echo "ZABBIX_API_TOKEN=your-generated-token" >> .env
   ```

3. **Redeploy:**

   ```bash
   sudo ./scripts/install.sh
   ```

4. **Verify in Grafana:**
   - Configuration → Data Sources → Zabbix
   - Click "Save & Test"
   - Should show: ✅ "Data source is working"

---

## 🔐 Security Improvements

| Feature | Username/Password | API Token |
|---------|------------------|-----------|
| **Token Expiration** | N/A | ✅ Optional expiration |
| **Revocation** | Password change required | ✅ Instant revocation |
| **Audit Trail** | User-level only | ✅ Token-specific logs |
| **Scope** | Full user permissions | ✅ Can be limited |
| **Rotation** | Affects all integrations | ✅ Per-integration |
| **Best Practice** | ❌ Not recommended | ✅ Industry standard |

---

## 📊 API Token Generation Guide

### Step-by-Step Instructions

```text
┌─────────────────────────────────────────────────────────────┐
│ Zabbix Web Interface                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Login as admin                                          │
│     └─ Navigate to Administration                           │
│                                                             │
│  2. Users                                                   │
│     └─ Select user for Grafana (e.g., "grafana")          │
│                                                             │
│  3. API tokens tab                                          │
│     └─ Click "Create API token"                            │
│                                                             │
│  4. Configure token                                         │
│     ├─ Description: "Grafana Integration"                  │
│     ├─ Expires at: [Leave empty or set date]              │
│     └─ Click "Add"                                         │
│                                                             │
│  5. Copy token                                              │
│     └─ Token shown ONCE - copy immediately!                │
│                                                             │
│  Example token format:                                      │
│  a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Required Permissions

User must have:

- ✅ User type: "User" or "Admin" (not "Guest")
- ✅ Frontend access: Enabled
- ✅ Read access to required host groups
- ✅ Permissions to view:
  - Hosts
  - Items
  - Triggers
  - History

---

## ✅ Validation Checklist

### Before Deployment

- [ ] Zabbix API token generated in Zabbix UI
- [ ] Token copied and stored securely
- [ ] ZABBIX_API_TOKEN set in .env file
- [ ] ZABBIX_USER removed from .env
- [ ] ZABBIX_PASSWORD removed from .env
- [ ] ZABBIX_URL verified (points to API endpoint)
- [ ] User permissions verified in Zabbix

### After Deployment

- [ ] Grafana container started successfully
- [ ] No warnings in install.sh output about deprecated variables
- [ ] Zabbix plugin installed (`podman exec grafana grafana-cli plugins ls`)
- [ ] Zabbix datasource exists in Grafana UI
- [ ] Datasource test passes (green checkmark)
- [ ] Can query Zabbix data in Explore view
- [ ] Dashboards display Zabbix metrics correctly

---

## 🐛 Troubleshooting

### Issue: "Authentication failed"

**Symptoms:**

- Datasource test fails
- Error message mentions authentication

**Solutions:**

1. Verify token is correct (regenerate if needed)
2. Check token hasn't expired
3. Verify user has proper permissions in Zabbix
4. Ensure token is for correct Zabbix user

**Verification:**

```bash
# Check environment variable in container
podman exec grafana printenv ZABBIX_API_TOKEN

# Test Zabbix API with token
curl -X POST http://zabbix.example.com/api_jsonrpc.php \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "apiinfo.version",
    "params": [],
    "auth": "YOUR_TOKEN_HERE",
    "id": 1
  }'
```

### Issue: Old variables still in use

**Symptoms:**

- Warnings during install.sh execution
- Datasource still shows username field

**Solutions:**

1. Remove ZABBIX_USER and ZABBIX_PASSWORD from .env
2. Run install script again
3. Restart Grafana container: `systemctl restart grafana.service`

**Verification:**

```bash
# Check .env file
grep -E "^ZABBIX_(USER|PASSWORD)=" .env
# Should return nothing

# Check for warnings
sudo ./scripts/install.sh 2>&1 | grep -i "deprecated"
# Should return nothing
```

### Issue: Token not working

**Symptoms:**

- Datasource test fails
- Token appears correct

**Solutions:**

1. Regenerate token in Zabbix
2. Verify user isn't disabled in Zabbix
3. Check user has API access enabled
4. Verify Zabbix frontend access isn't blocked

**Verification:**

```bash
# Test Zabbix API directly
curl http://zabbix.example.com/api_jsonrpc.php
# Should return Zabbix version info
```

---

## 📚 References

### Documentation Links

- **Grafana Zabbix Plugin:**
  <https://grafana.com/grafana/plugins/alexanderzobnin-zabbix-app/>
- **Zabbix API Documentation:**
  <https://www.zabbix.com/documentation/current/en/manual/api>
- **Zabbix API Tokens:**
  <https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/api_tokens>

### Related Files

- `.env.example` - Environment template with API token configuration
- `configs/grafana/provisioning/datasources/datasources.yaml` - Datasource configuration
- `quadlets/grafana.container` - Grafana Quadlet with environment variables
- `scripts/install.sh` - Installation script with validation
- `README.md` - Main documentation with Zabbix integration guide
- `VARIABLES_REFERENCE.md` - Complete variable reference

---

## 📈 Benefits Summary

### Security

✅ Token-based authentication (industry standard)
✅ Per-integration tokens (better isolation)
✅ Instant revocation capability
✅ Optional expiration dates
✅ Better audit trails

### Operational

✅ Required by Grafana Zabbix plugin
✅ Easier credential rotation
✅ No impact on user password
✅ Clear deprecation path
✅ Comprehensive documentation

### Compliance

✅ Follows security best practices
✅ Aligns with CONTEXT.md standards
✅ No secrets in git
✅ Clear migration path
✅ Backward compatibility warnings

---

## 📅 Timeline

- **2026-01-28:** Migration implemented
- **Status:** Complete and ready for deployment
- **Breaking Change:** Yes (username/password no longer supported)
- **Migration Required:** Yes (for existing deployments)
- **Documentation:** Complete

---

**Status:** ✅ **Complete**
**Version:** 1.2.0
**Breaking Change:** Yes
**Migration Guide:** Included above
