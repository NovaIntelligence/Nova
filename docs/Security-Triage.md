# Security Triage Workflow

When `security.yml` fails (Gitleaks/Trivy), follow this process:

## 1. Identify the failing scanner
- Check PR checks → `security` workflow → which step failed (Gitleaks/Trivy FS/Trivy Config).
- Download SARIF artifacts (`artifacts/security/*`) if you prefer local review.

## 2. Classify issues
- Secrets (Gitleaks):
  - True positive → Rotate or remove; migrate to GitHub Encrypted Secrets or Vault.
  - False positive → Tune `security/gitleaks/gitleaks.toml` with tight, scoped allow rules.
- Vulnerabilities (Trivy FS):
  - Library/package → Update pinned versions; regenerate lockfiles; document CVE if risk accepted.
  - OS-level → Update base images or packages; prefer fixed tags.
- Misconfigurations (Trivy Config):
  - Fix insecure defaults (privileged containers, no resource limits, plaintext secrets, etc.).
  - Document rationale if intentionally deviating with compensating controls.

## 3. Remediate
- Create a branch per remediation area; keep changes small and reviewable.
- Reference the SARIF finding IDs/CVEs in the PR description.

## 4. Verify
- Re-run `security` workflow on your branch; ensure the failing step is now green.

## 5. Document exceptions
- If an issue cannot be fixed immediately, add a narrow suppression and justification in the repo (e.g., `security/gitleaks/` or `security/trivy/` policy notes) and open a follow-up issue with a target date.
