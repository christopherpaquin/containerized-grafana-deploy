# 📘 AI Code Review Prompt & Repository Export Guide v1

This document provides a **standardized workflow** for having AI tools such as **ChatGPT, Claude, and Gemini**
review a code repository accurately and thoroughly.

It includes:

- How to export a repo so AI can read it

- A universal prompt that works across AI models

- A structured review framework

- Best practices for infra / automation projects

* * * * *

## ✅ STEP 1: Export the Repository for AI Review

AI models **cannot read GitHub links directly**.\
You must provide the code explicitly.

* * * * *

## 🔹 Option A --- Recommended: ZIP the Repository

From inside your repo:

`git archive --format=zip -o repo-review.zip HEAD`

Then upload:

`repo-review.zip`

This works reliably with:

- ChatGPT

- Claude

- Gemini

* * * * *

## 🔹 Option B --- Create a Single Review File (Best for Large Repos)

Use this script to generate a consolidated review bundle:

`#!/usr/bin/env bash
set -euo pipefail

OUT="AI_REVIEW_BUNDLE.txt"
: > "$OUT"

echo "## REPOSITORY TREE" >> "$OUT"
git ls-files | sed 's/^/- /' >> "$OUT"
echo >> "$OUT"

FILES=(
  "README.md"
  "QUICKSTART.md"
  ".env.example"
  "scripts"
)

for f in "${FILES[@]}"; do
  if [[ -e "$f" ]]; then
    echo "## FILE: $f" >> "$OUT"
    echo '```' >> "$OUT"
    if [[ -d "$f" ]]; then
      find "$f" -type f -exec sed -n '1,400p' {} \;
    else
      sed -n '1,400p' "$f"
    fi
    echo '```' >> "$OUT"
    echo >> "$OUT"
  fi
done

echo "Review bundle created: $OUT"`

Upload:

`AI_REVIEW_BUNDLE.txt`

* * * * *

## ✅ STEP 2: AI REVIEW PROMPT (COPY & PASTE)

Paste **everything below** into ChatGPT, Claude, or Gemini after uploading the repo or bundle.

* * * * *

## 🔍 AI Code Review Request

You are reviewing a software repository provided as an uploaded archive or pasted content.

### 🎯 Objectives

Perform a **deep technical review** focused on:

- Correctness

- Security

- Idempotency

- Maintainability

- Documentation quality

- Production readiness

This repository is used for:

- Infrastructure automation

- Containerized deployments

- System-level configuration

- Long-running services

* * * * *

### 🧠 Tasks

#### 1️⃣ Code Structure Review

- Explain the purpose of each major file

- Identify duplication or unnecessary complexity

- Highlight unclear or fragile logic

#### 2️⃣ Shell / Script Quality

- Identify unsafe shell practices

- Check quoting and variable handling

- Review error handling and exit behavior

- Flag missing `set -euo pipefail`, traps, or logging

- Identify brittle command usage

#### 3️⃣ Idempotency Review (**Critical**)

For each of the following, determine whether re-running is safe:

- File creation

- Container creation

- Firewall rules

- Users

- Certificates

- Volumes

- Services

Answer:

- Is it safe to re-run?

- Does it detect existing state?

- Can it cause duplication or corruption?

#### 4️⃣ Security Review

Evaluate:

- Secret handling

- Environment variable usage

- File permissions

- TLS behavior

- Firewall exposure

- Privilege level (root vs rootless)

- SELinux considerations (if applicable)

#### 5️⃣ Container & Deployment Review

- Environment variable propagation

- Volume mounting

- Startup order

- Health checks

- Restart behavior

- Failure recovery

#### 6️⃣ Documentation Review

- Accuracy of README

- Redundant or outdated sections

- Missing explanations

- What should move to `docs/`

- What should be simplified

#### 7️⃣ Improvements & Refactors

For each issue:

- Explain the problem

- Suggest a fix

- Provide example code or diffs where appropriate

* * * * *

### 📤 Required Output Format

Please respond using the following structure:

```text
## Summary

## Critical Issues

## Medium Priority Issues

## Minor Improvements

## Security Review

## Idempotency Review

## Documentation Feedback

## Suggested Refactors

## Final Recommendations
```

* * * * *

## ✅ STEP 3: Recommended Workflow

1. Export repo (`zip` or `bundle`)

2. Upload to AI

3. Run this prompt

4. Apply fixes in Cursor

5. Re-run review

6. Finalize documentation

* * * * *

## 🧠 Best Tool Pairing

| Tool | Best Use |
| --- | --- |
| Claude | Architecture & reasoning |
| ChatGPT | Refactoring & explanations |
| Gemini | Code smell detection |
| Cursor | Implementing fixes |

* * * * *

## ⚠️ Important Notes

- AI **cannot** browse GitHub

- Links alone are insufficient

- Files must be uploaded or pasted

- ZIP files work best

- Large repos should use the bundle method

* * * * *

## ✅ Optional Enhancements

If desired, this template can be adapted for:

- 🔐 Security audits

- 🧪 CI/CD validation

- 🧱 Infrastructure-as-Code review

- 📦 Container hardening

- 📚 Documentation audits

* * * * *
