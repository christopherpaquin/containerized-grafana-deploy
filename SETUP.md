# 🔧 Environment Setup Guide

This guide walks you through setting up your development environment to use this GitHub AI Engineering Framework.

---

## 📋 Prerequisites

Before you begin, ensure you have the following installed on your system:

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| **Python** | 3.11+ | Required for pre-commit and linting tools |
| **pip** | Latest | Python package installer |
| **git** | 2.x+ | Version control |
| **bash** | 4.x+ | Shell scripting |

### System Requirements

- **Primary OS**: RHEL 9/10 or Ubuntu 22.04+
- **Shell**: bash (required for scripts)
- **Internet**: Required for installing dependencies

---

## 🚀 Step-by-Step Setup

### Step 1: Verify Python Installation

Check if Python 3.11+ is installed:

```bash
python3 --version
```

**Expected output**: `Python 3.11.x` or higher

**If not installed**:

**Ubuntu/Debian**:

```bash
sudo apt update
sudo apt install python3 python3-pip python3-venv
```

**RHEL/Rocky/AlmaLinux**:

```bash
sudo dnf install python3.11 python3.11-pip
```

**Verify pip is installed**:

```bash
pip3 --version
```

### Step 2: Clone the Repository

If you haven't already cloned this repository:

```bash
git clone <your-repo-url>
cd <your-repo-name>
```

### Step 3: Install Pre-commit

Pre-commit is the **core quality enforcement tool** in this framework. It must be installed system-wide or in a virtual environment.

**Option A: Install system-wide (recommended for ease of use)**:

```bash
pip3 install --user pre-commit
```

**Option B: Install in a virtual environment (isolated)**:

```bash
# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # Linux/macOS
# OR
.venv\Scripts\activate     # Windows

# Install pre-commit
pip install pre-commit
```

**Verify installation**:

```bash
pre-commit --version
```

**Expected output**: `pre-commit 3.x.x` or similar

### Step 4: Install Pre-commit Hooks

This is the **critical step** that enables automatic pre-commit checks on
every commit.

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

**Expected output**:

```text
pre-commit installed at .git/hooks/pre-commit
pre-commit installed at .git/hooks/commit-msg
```

**What this does**:

- Installs a git hook in `.git/hooks/pre-commit` that runs on every commit
- Installs a git hook in `.git/hooks/commit-msg` that validates commit messages
- The hooks run automatically every time you run `git commit`
- Checks code quality, formatting, security, and commit messages before allowing the commit

### Step 5: Verify Hook Installation

Check that the hook was installed correctly:

```bash
ls -la .git/hooks/pre-commit
```

**Expected output**: The file should exist and be executable

**Check hook content**:

```bash
head -5 .git/hooks/pre-commit
```

**Expected output**: Should show pre-commit shebang and comments

### Step 6: Install Pre-commit Environments

Pre-commit needs to download and set up tool environments (Ruff, ShellCheck, etc.).
This happens automatically on first run, but you can do it manually:

```bash
pre-commit install-hooks
```

**What this does**:

- Downloads all the tools defined in `.pre-commit-config.yaml`
- Sets up isolated environments for each tool
- This can take 2-5 minutes on first run
- Subsequent runs will be much faster

### Step 7: Test Your Setup

Run pre-commit on all files to verify everything works:

```bash
./template/scripts/run-precommit.sh
```

**Expected output**:

```text
Running pre-commit checks...
Log file: /path/to/artifacts/pre-commit.log
Repository: /path/to/repo
Timestamp: 2026-01-23T...

check for merge conflicts................................................Passed
check yaml...............................................................Passed
check json...............................................................Passed
...
✅ pre-commit passed successfully
```

**If you see errors**: Review `artifacts/pre-commit.log` for details.

### Step 8: Test Automatic Commit Hook

Create a test commit to verify hooks run automatically:

```bash
# Make a trivial change
echo "# Test" >> test.txt
git add test.txt

# Try to commit (pre-commit should run automatically)
git commit -m "Test pre-commit hook"
```

**Expected behavior**:

- Pre-commit hooks should run automatically
- You should see the same checks as in Step 7
- If checks pass, commit succeeds
- If checks fail, commit is blocked

**Clean up test file**:

```bash
git reset HEAD~1  # Undo the commit
rm test.txt       # Remove test file
```

---

## 🔍 Troubleshooting

### Issue: "pre-commit: command not found"

Cause: Pre-commit is not in your PATH.

Solution:

```bash
# Add pip user directory to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

### Issue: Pre-commit doesn't run on git commit

Cause: Hooks are not installed.

Solution:

```bash
# Install hooks
pre-commit install

# Verify installation
ls -la .git/hooks/pre-commit
```

If the hook file exists but doesn't run:

```bash
# Make hook executable
chmod +x .git/hooks/pre-commit

# Try commit again
```

### Issue: "scripts/detect-secrets.sh: No such file or directory"

Cause: The script path in `.pre-commit-config.yaml` is incorrect.

Solution: The script should be at `template/scripts/detect-secrets.sh`. Update the config:

```yaml
- repo: local
  hooks:
    - id: detect-secrets
      name: Detect Secrets (API Keys, Tokens, Credentials)
      entry: template/scripts/detect-secrets.sh
      language: system
```

### Issue: Python version too old

Cause: Python 3.11+ is required.

Solution:

```bash
# Install Python 3.11 or higher
# See Step 1 for OS-specific instructions

# Specify Python version for pre-commit
pre-commit install --install-hooks --python python3.11
```

### Issue: "permission denied" when running scripts

Cause: Scripts are not executable.

Solution:

```bash
# Make scripts executable
chmod +x template/scripts/*.sh
chmod +x template/bootstrap-template-structure.sh
```

### Issue: Pre-commit is very slow on first run

**This is normal**: Pre-commit downloads and installs tool environments on first run. Subsequent runs will be much faster.

---

## 🎯 Verification Checklist

Use this checklist to ensure your environment is properly set up:

- [ ] Python 3.11+ is installed (`python3 --version`)
- [ ] pip is installed (`pip3 --version`)
- [ ] Pre-commit is installed (`pre-commit --version`)
- [ ] Pre-commit hooks are installed (`ls .git/hooks/pre-commit`)
- [ ] Pre-commit runs automatically on commit (test with a dummy commit)
- [ ] Manual pre-commit run succeeds (`./template/scripts/run-precommit.sh`)
- [ ] All scripts are executable (`ls -la template/scripts/*.sh`)

---

## 🔄 Daily Workflow

Once your environment is set up, your typical workflow is:

1. Make code changes

2. Stage files: `git add <files>`

3. Commit: `git commit -m "message"`
   - Pre-commit runs automatically
   - If checks fail, fix issues and commit again

4. Push: `git push`

**Alternative workflow** (manual pre-commit):

1. Make code changes

2. Run pre-commit manually: `./template/scripts/run-precommit.sh`

3. Fix any issues

4. **Stage and commit**: `git add . && git commit -m "message"`

5. **Push**: `git push`

---

## 📚 Additional Tools (Optional)

### ShellCheck (for shell script validation)

Pre-commit uses ShellCheck automatically, but you can install it locally for IDE integration:

**Ubuntu/Debian**:

```bash
sudo apt install shellcheck
```

**RHEL/Rocky/AlmaLinux**:

```bash
sudo dnf install ShellCheck
```

### Ruff (for Python linting)

Pre-commit uses Ruff automatically, but you can install it locally:

```bash
pip3 install ruff
```

---

## 🆘 Getting Help

If you encounter issues not covered in this guide:

1. **Check pre-commit logs**: `cat artifacts/pre-commit.log`

2. **Review framework documentation**: `template/docs/ai/CONTEXT.md`

3. **Check CI configuration**: `.github/workflows/ci.yaml`

4. **Review issue templates**: `.github/ISSUE_TEMPLATE/`

---

## 🔗 Next Steps

After completing this setup:

1. **Read**: `README.md` for framework overview

2. **Review**: `template/docs/ai/CONTEXT.md` for AI agent standards

3. **Customize**: `template/docs/requirements.md` for your project

4. **Start coding**: The framework will enforce quality automatically

---

## 📄 Quick Reference

| Command | Purpose |
|---------|---------|
| `pre-commit install` | Install git hooks (run once) |
| `pre-commit uninstall` | Remove git hooks |
| `./template/scripts/run-precommit.sh` | Run checks manually |
| `pre-commit run --all-files` | Run checks on all files |
| `pre-commit clean` | Clean up cached environments |
| `pre-commit autoupdate` | Update hook versions |

---

**✅ Setup complete!** You're ready to use the GitHub AI Engineering Framework.
