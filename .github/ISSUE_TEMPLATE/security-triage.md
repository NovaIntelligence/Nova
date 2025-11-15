---
name: "Security Triage"
about: "Track triage/remediation for a security finding (Gitleaks/Trivy/CodeQL)."
title: "Security: [Scanner] [Rule/CVE] short summary"
labels: ["security:triage"]
assignees: []
---

## Source

- Scanner: Gitleaks | Trivy FS | Trivy Config | CodeQL | Other
- Workflow run: <link to Actions run or SARIF>
- Branch/Commit: <!-- e.g., main @ abcdef1 -->

## Finding Details

- Severity: Critical | High | Medium | Low | Info
- Rule/CVE/Query ID: <!-- e.g., CVE-2024-XXXX or ql/java/... -->
- Affected path/resource: <!-- file path or IaC resource -->
- Evidence: <!-- snippet, secret fingerprint, dependency version, etc. -->

## Impact Assessment

- What can be exploited or leaked?
- Is this reachable or used in production paths?
- Is there a public exposure or history (git history, artifacts)?

## Owner and Plan

- Owner: @username
- Proposed fix: remove/rotate secret | upgrade/patch dependency | change config | suppress with justification | other
- ETA: <!-- date -->

## Checklist

- [ ] Validate finding against evidence/logs
- [ ] Set correct severity and labels (`security:secret` | `security:vuln` | `security:config`)
- [ ] Notify stakeholders (if production/user data affected)
- [ ] Implement fix or mitigation
- [ ] Add/adjust tests and CI gates
- [ ] Verify remediation (rerun scans)

## Notes

Reference: `docs/security/SECURITY_TRIAGE.md`