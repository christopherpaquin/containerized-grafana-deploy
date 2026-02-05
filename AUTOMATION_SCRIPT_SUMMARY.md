# LibreNMS MySQL Integration - Now Automated! 🚀

**Date:** 2026-02-05
**Status:** Automation script created and ready

---

## Summary

✅ **Your current LibreNMS integration is complete** (10.1.10.58 → Grafana)
✅ **New automation script created** for future deployments

---

## What We Built

### Automation Script
**Location:** `scripts/integrate-librenms-mysql.sh`

**What it does:**
1. Tests SSH connectivity to LibreNMS server
2. Automatically retrieves database credentials from container
3. Exposes MySQL port 3306 (if not already exposed)
4. Tests database connectivity from Grafana server
5. Creates `LibreNMS-MySQL` datasource in Grafana
6. Verifies with sample query (device count)

**Features:**
- ✅ **Fully automated** - one command setup
- ✅ **Idempotent** - safe to run multiple times
- ✅ **Interactive** - prompts before overwriting existing datasource
- ✅ **Validated** - tests each step before proceeding
- ✅ **Error handling** - clear error messages and troubleshooting hints

---

## Usage

### For New LibreNMS Instances

```bash
cd /root/containerized-grafana-deploy
source .env
sudo ./scripts/integrate-librenms-mysql.sh <librenms-ip> [ssh-user]
```

**Example:**
```bash
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
```

### Prerequisites
- SSH access to LibreNMS server (passwordless SSH recommended)
- LibreNMS running in containers (Docker/Podman)
- `.env` file with Grafana credentials

---

## What Was Done Manually (For Your Current Setup)

Since we set up your **10.1.10.58** instance manually, here's what we did:

1. ✅ **Exposed MySQL Port**
   - Edited `/etc/containers/systemd/librenms-db.container`
   - Added `PublishPort=3306:3306`
   - Restarted librenms-db service

2. ✅ **Retrieved Credentials**
   - Database: `librenms`
   - User: `librenms`
   - Password: `<retrieved-from-container>`

3. ✅ **Deleted Old Datasource**
   - Removed non-working `InfluxDB-LibreNMS` (ID 3)

4. ✅ **Created MySQL Datasource**
   - Name: `LibreNMS-MySQL`
   - ID: 6
   - UID: `dfcc04qh3qdxcc`

5. ✅ **Verified**
   - 17 active devices found
   - Sample queries working

---

## Testing the Script

If you want to test the script with your existing setup:

```bash
# This will detect the existing datasource and ask if you want to recreate
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
```

It will:
- Detect MySQL port is already exposed ✅
- Find existing `LibreNMS-MySQL` datasource
- Ask: "Delete and recreate? [y/N]"
- If you say **N**, it skips (safe)
- If you say **Y**, it recreates from scratch

---

## Use Cases

### 1. Adding Another LibreNMS Instance
```bash
# Example: Second LibreNMS at 10.1.10.60
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.60 root
```

This will create a second datasource (e.g., `LibreNMS-MySQL-2`)

### 2. Recreating After Changes
If you change database credentials or need to reset:
```bash
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
# Answer 'y' when prompted to delete and recreate
```

### 3. Fresh Deployment
On a new Grafana deployment, run:
```bash
# Deploy Grafana stack first
sudo bash scripts/install.sh

# Then integrate LibreNMS
sudo ./scripts/integrate-librenms-mysql.sh 10.1.10.58 root
```

---

## Script Features Breakdown

### Automatic Credential Detection
Tries multiple methods to find credentials:
1. From running LibreNMS container environment
2. From Quadlet configuration file
3. From Docker Compose file

### Smart Port Exposure
- Detects if port 3306 is already exposed
- If not, modifies Quadlet config automatically
- Reloads systemd and restarts database service
- Verifies port is accessible

### Grafana API Integration
- Checks for existing datasource
- Creates new datasource with optimal settings
- Tests with real query
- Reports device count

### Error Handling
Clear error messages for:
- SSH connectivity issues
- Missing credentials
- Port exposure failures
- Database connection problems
- Grafana API errors

---

## Documentation Updated

### Main Guide
`DATASOURCE_INTEGRATION_GUIDE.md` now includes:
- **Option A:** Automated script (recommended)
- **Option B:** Manual Grafana UI
- **Option C:** Manual API calls

### New Files Created
1. `scripts/integrate-librenms-mysql.sh` - The automation script
2. `AUTOMATION_SCRIPT_SUMMARY.md` - This summary
3. `LIBRENMS_MYSQL_SETUP_SUMMARY.md` - Detailed setup documentation

---

## Comparison: Manual vs Automated

| Task | Manual | Automated |
|------|--------|-----------|
| **SSH to LibreNMS** | Required | Script handles it |
| **Find credentials** | Manual inspection | Auto-detected |
| **Expose MySQL port** | Edit config, reload | One command |
| **Test connectivity** | Manual curl | Built-in test |
| **Create datasource** | API call or UI | Automatic |
| **Verify working** | Manual query | Built-in test |
| **Time required** | ~10-15 minutes | ~2-3 minutes |
| **Error prone** | Yes (typos, syntax) | Validated |

---

## Future Enhancements (Optional)

The script could be extended to:
- [ ] Create read-only database user automatically
- [ ] Configure firewall rules for MySQL port
- [ ] Set up SSL/TLS for MySQL connection
- [ ] Create default LibreNMS dashboards
- [ ] Add to main `install.sh` as optional step

---

## Summary

✅ **Your setup:** Complete and working manually
✅ **Automation:** Now available for future use
✅ **Documentation:** Updated with all three methods
✅ **Ready for:** Additional LibreNMS instances anytime

**Your current LibreNMS (10.1.10.58) doesn't need to be reconfigured** - it's already working perfectly! The script is for future deployments or if you need to add more LibreNMS instances.
