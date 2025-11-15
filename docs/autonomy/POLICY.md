# Nova Autonomy Policy

Last updated: 2025-11-16

Purpose: Define guardrails for low-risk, autonomous changes made by bots/automation while preserving safety, ownership, and accountability.

## Allowed Changes (Low Risk)
- Docs only: `**/*.md`, `docs/**`, `README*`
- CI metadata: `.github/**` except executable scripts; workflow pin updates only (SHA pin or comment-only changes)
- Security configs: `.trivyignore`, `security/gitleaks/**`, `security/trivy/policies/**` (additive noise-tuning only)
- Codeowners/labels: `.github/CODEOWNERS`, label workflows, triage templates
- Non-executable assets: `*.json` (metadata), `*.yaml` (configs), images under `assets/`

## Disallowed (Require Human Review)
- Application code under: `core/**`, `services/**`, `apps/**`, `platform/**`, `backend/**`, `src/**` (any language)
- Auth/Secrets: `auth/**`, `secrets/**`, `creds/**`, `env/**`
- Infra changes: `ops/**`, `cloudrun/**`, `gcp/**`, `nova-stack/**` (except readme/docs)
- Any shell/powershell/python/node scripts: `**/*.sh`, `**/*.ps1`, `**/*.py`, `**/*.js`, `**/*.ts`

## Risk Classes
- Low: strictly within Allowed set and additive only (no deletions of protections).
- Medium: touches infra configs or build scripts; requires 1 owner approval.
- High: changes executable code, auth, or prod infra; requires 2 approvals and cannot be autonomous.

## Required Signals
- Passing CI + security checks (tests, CodeQL, pr-security matrix) on PR.
- CODEOWNERS review required for Medium/High.
- Labels used: `autonomy:task` for queued work, `autonomy:review` to pause, `autonomy:off` to kill-switch.

## Kill-Switch
- If `autonomy:off` label exists on a PR or Issue, bots must halt changes and auto-merge.
- If `autonomy:review` present, proceed only to open PR, do not auto-merge.

## Auditability
- All automated PRs must link to a source Issue and record:
  - Who/what initiated it, timestamp, diff summary, and policy risk class.

## Enforcement
- `autonomy-gate` workflow validates path allowlist and risk. Out-of-policy changes fail the gate when initiated by bots.
- Security and governance gates remain required on `main`.
