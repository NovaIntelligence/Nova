# Nova Repository Health Assessment

- Date: 2025-11-15
- Assessor: Tyler / Nova
- Goal: Foundation ready for high-value skills & no-debt growth

## Current State Summary

Here’s a structured snapshot of the repo as it stands, with scores and next steps for improving reliability, security, and readiness for high-value skills.

### Overall

Summary: Solid foundations with real CI, smoke tests, and wired security scans. The governance gate is a strong plus. Biggest gaps: action pinning, broader test coverage, and finishing the move to fully blocking security.

Overall Score: 8.1 / 10

---

### CI/CD — 8.4 / 10

Strengths:
- ci.yml: Blocking Pester tests on a Windows matrix, PSScriptAnalyzer at Severity = Error, conditional dotnet build, plus top-level permissions and concurrency.
- codeql.yml: Weekly schedule, continue-on-error removed, permissions + concurrency configured.
- governance-metrics-gate.yml: Enforces metrics JSON for critical paths, expanded infra regex, permissions + concurrency added.
- docs.yml: Permissions + concurrency wired, simple build placeholder in place.
- pages.yml: Re-added with a generated static index, correct Pages permissions and concurrency configured.

Gaps:
- Actions are not pinned to commit SHAs (supply chain risk).
- Lint currently focuses on tools/skills, tests, and modules—not all directories.
- Legacy test workflows (pester.yml, skills-smoke.yml) still exist as standalone/manual.

---

### Security & Supply Chain — 8.2 / 10

Strengths:
- security.yml runs real scans:
  - Gitleaks with --redact and repo config, SARIF uploaded.
  - Syft SBOM (SPDX JSON) as an artifact.
  - Trivy filesystem vuln scan + config scan, both blocking with exit-code: '1'.
- SARIF surfaced into the Security tab via code scanning.

Gaps:
- Actions are not pinned to SHAs (e.g. actions/checkout, gitleaks, Trivy).
- If the baseline has leaks/vulns, PRs will fail until triaged and fixed—needs a clear owner workflow.
- No secrets scanning guardrail locally/pre-commit—only in CI.

---

### Testing — 7.5 / 10

Strengths:
- Smoke tests (Skills.Smoke.Tests.ps1) cover:
  - Outbound-Deal-Machine.ps1 (safe-by-default emailing).
  - Offer-Architect.ps1 (template rendering, ad variants).
  - Self-Sufficiency-Model.ps1 (calculations and report generation).
- Tests are green locally; CI tests are now blocking.

Gaps:
- Only smoke-level tests; minimal coverage for edge cases, invalid inputs, or error paths.
- No coverage gate (NUnit artifacts exist but no enforced thresholds).

---

### Linting & Style — 7.9 / 10

Strengths:
- PSScriptAnalyzer configured via pssa.settings.psd1 (Error-only), blocking in CI.
- Scope extended to modules.
- CmdletBinding() + Set-StrictMode and safe defaults used consistently in key skills (e.g. Offer-Architect.ps1).
- .config/pssa.suppressions.md documents suppression guidance.

Gaps:
- Rule set is minimal; IncludeRules not tuned to repo conventions and ExcludeRules unset.
- Inline suppressions are not yet used where intentional patterns exist.

---

### Governance & Process — 8.6 / 10

Strengths:
- Governance metrics gate enforced for infra/scale paths with expanded regex coverage.
- Dependabot configured for Actions, npm, pip, and nuget (weekly).
- Auto-merge remains enabled after checks pass, preserving good flow.

Gaps:
- No visible CODEOWNERS file for critical areas.
- No dedicated change-management template for governance metrics JSON (only README guidance).

---

### Documentation & Pages — 8.0 / 10

Strengths:
- README is rich: badges, quick skills, architecture notes, and examples.
- “Security Scans & Triage” section added.
- Pages workflow in place with a minimal generated index; correct permissions and concurrency.

Gaps:
- No dedicated docs site build (placeholder only), no navigation or versioning.
- Pages badge could be added once a public URL is live.

---

### Runtime Robustness (PowerShell Skills) — 7.8 / 10

Strengths:
- Skills use safe defaults: outbound mail gated by both flag and env; input validation; clean output dirs.
- Self-Sufficiency-Model.ps1: good validation and structured output.

Gaps:
- Error handling for malformed CSV rows/templates is basic; UX could be improved with clearer messages.
- A central utilities module for logging/error patterns isn’t consistently referenced yet (Nova.Common is mentioned in docs but not widely used here).

---

### Maintainability & Structure — 8.0 / 10

Strengths:
- Workflows separated by purpose; concurrency + permissions are consistently applied.
- Artifacts uploaded for lint, tests, and security to support triage.

Gaps:
- Large repo footprint; not all directories are governed by tests/lint (by design).
- Scope decisions could be more explicitly documented to avoid confusion for new contributors.

---

### Weighted Overall Score

- Categories: CI/CD, Security, Testing, Linting, Governance, Docs, Runtime Robustness, Maintainability.
- Method: Equal weights.
- Average: (8.4 + 8.2 + 7.5 + 7.9 + 8.6 + 8.0 + 7.8 + 8.0) / 8 = 8.1 / 10

---

## High-Impact Next Steps

1. Pin GitHub Actions to SHAs (Security/Supply Chain)
- Replace @v4, @v3, etc. with commit SHAs in:
  - ci.yml, security.yml, codeql.yml, docs.yml, pages.yml, governance-metrics-gate.yml.

2. Expand Tests for Money-Critical Skills
- Add edge-case/unit tests for:
  - Self-Sufficiency-Model.ps1: invalid/missing params, negative values, extreme scenarios.
  - Outbound-Deal-Machine.ps1: missing CSV columns, empty/malformed rows.
  - Offer-Architect.ps1: missing template tokens, invalid input structures.

3. Tighten PSScriptAnalyzer Rules Gradually
- Extend pssa.settings.psd1 with a minimal curated rule set (e.g. AvoidUsingWriteHost, whitespace/formatting).
- Use inline suppressions with justification for intentional patterns.

4. Define Security Triage Workflow
- Document how to handle failing Gitleaks/Trivy runs:
  - Rotate/remove/test secrets vs. adding patterns to security/gitleaks/gitleaks.toml.
  - Upgrade vulnerable libs or Dockerfiles, with narrowly scoped CVE suppressions only when justified.

5. Governance & Docs Enhancements
- Add a CODEOWNERS file for critical paths (skills, infra, security).
- Add a sample governance metrics JSON file to the repo, linked from README.
- Enable Pages (GitHub Actions) in settings so the basic index is live; iterate into a docs site later.

Creators: Tyler McKendry & Nova
