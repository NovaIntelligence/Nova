# Security Triage Workflow

When CI security checks fail (Gitleaks or Trivy), follow this playbook.

## 1) Identify and Classify
- Open GitHub → Security → Code scanning alerts
- Filter by tool: Gitleaks, Trivy
- Classify:
  - Secrets (Gitleaks): live secrets vs. test data vs. false positive
  - Vulnerabilities (Trivy): HIGH/CRITICAL runtime libs; Config: misconfigurations

## 2) Respond
- Gitleaks (Secrets)
  - Live secret: revoke/rotate at source immediately
  - Remove from repo history if needed (BFG / git filter-repo), then re-run
  - Add masked env/secret store usage; never commit secrets
  - Only add patterns to `security/gitleaks/gitleaks.toml` for proven false positives (narrow scope)

- Trivy (Vulnerabilities)
  - Update vulnerable packages/lockfiles; bump base images if using containers
  - If unavoidable, add a narrowly scoped ignore (specific CVE) with justification
  - Re-scan locally if possible, then push fix

## 3) Verify
- Re-run checks (push a trivial change or use `workflow_dispatch`)
- Ensure SARIF alerts are resolved/closed

## 4) Document
- In PR description, note:
  - What failed, root cause, what changed, any remaining risks
  - Links to alerts and remediation commits

## References
- Gitleaks rules: `security/gitleaks/gitleaks.toml`
- SBOM: `artifacts/security/sbom.spdx.json`
- Trivy SARIF: `artifacts/security/trivy-fs.sarif`, `artifacts/security/trivy-config.sarif`
