#!/usr/bin/env bash
###############################################################################
# bootstrap-template-structure.sh
#
# Sets up project structure by copying template files to project root.
#
# Usage:
#   ./template/bootstrap-template-structure.sh
#
# This script:
# - Copies documentation templates from template/docs/ to project docs/
# - Copies scripts from template/scripts/ to project scripts/
# - Creates necessary directory structure
# - Does NOT overwrite existing files
###############################################################################

set -euo pipefail

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> GitHub AI Engineering Framework Bootstrap"
echo "Template directory: ${TEMPLATE_DIR}"
echo "Project root: ${PROJECT_ROOT}"
echo

# Directories to create in project root
DIRS=(
  "docs"
  "docs/ai"
  "docs/governance"
  "scripts"
)

echo "==> Creating directory structure"

for dir in "${DIRS[@]}"; do
  if [[ -d "${PROJECT_ROOT}/${dir}" ]]; then
    echo "✓ Directory exists: ${dir}"
  else
    mkdir -p "${PROJECT_ROOT}/${dir}"
    echo "✓ Created directory: ${dir}"
  fi
done

echo
echo "==> Copying template files (no overwrite)"

# Copy documentation files
if [[ ! -f "${PROJECT_ROOT}/docs/ai/CONTEXT.md" ]]; then
  cp "${TEMPLATE_DIR}/docs/ai/CONTEXT.md" "${PROJECT_ROOT}/docs/ai/"
  echo "✓ Copied: docs/ai/CONTEXT.md"
else
  echo "⊘ Skip (exists): docs/ai/CONTEXT.md"
fi

if [[ ! -f "${PROJECT_ROOT}/docs/requirements.md" ]]; then
  cp "${TEMPLATE_DIR}/docs/requirements.md" "${PROJECT_ROOT}/docs/"
  echo "✓ Copied: docs/requirements.md"
else
  echo "⊘ Skip (exists): docs/requirements.md"
fi

if [[ ! -f "${PROJECT_ROOT}/docs/ci-and-precommit.md" ]]; then
  cp "${TEMPLATE_DIR}/docs/ci-and-precommit.md" "${PROJECT_ROOT}/docs/"
  echo "✓ Copied: docs/ci-and-precommit.md"
else
  echo "⊘ Skip (exists): docs/ci-and-precommit.md"
fi

if [[ ! -f "${PROJECT_ROOT}/docs/security-ci-review.md" ]]; then
  cp "${TEMPLATE_DIR}/docs/security-ci-review.md" "${PROJECT_ROOT}/docs/"
  echo "✓ Copied: docs/security-ci-review.md"
else
  echo "⊘ Skip (exists): docs/security-ci-review.md"
fi

# Copy scripts
if [[ ! -f "${PROJECT_ROOT}/scripts/run-precommit.sh" ]]; then
  cp "${TEMPLATE_DIR}/scripts/run-precommit.sh" "${PROJECT_ROOT}/scripts/"
  chmod +x "${PROJECT_ROOT}/scripts/run-precommit.sh"
  echo "✓ Copied: scripts/run-precommit.sh"
else
  echo "⊘ Skip (exists): scripts/run-precommit.sh"
fi

if [[ ! -f "${PROJECT_ROOT}/scripts/detect-secrets.sh" ]]; then
  cp "${TEMPLATE_DIR}/scripts/detect-secrets.sh" "${PROJECT_ROOT}/scripts/"
  chmod +x "${PROJECT_ROOT}/scripts/detect-secrets.sh"
  echo "✓ Copied: scripts/detect-secrets.sh"
else
  echo "⊘ Skip (exists): scripts/detect-secrets.sh"
fi

if [[ ! -f "${PROJECT_ROOT}/scripts/check-commit-message.sh" ]]; then
  cp "${TEMPLATE_DIR}/scripts/check-commit-message.sh" "${PROJECT_ROOT}/scripts/"
  chmod +x "${PROJECT_ROOT}/scripts/check-commit-message.sh"
  echo "✓ Copied: scripts/check-commit-message.sh"
else
  echo "⊘ Skip (exists): scripts/check-commit-message.sh"
fi

echo
echo "==> Bootstrap complete!"
echo
echo "Next steps:"
echo "1. Review and customize docs/requirements.md for your project"
echo "2. Install pre-commit: pip install pre-commit"
echo "3. Install hooks: pre-commit install"
echo "4. Run pre-commit: ./scripts/run-precommit.sh"
echo
echo "See SETUP.md for detailed environment setup instructions."
