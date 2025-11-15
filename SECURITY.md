# Security Policy

We take security seriously. This document explains how to report vulnerabilities and how we triage and remediate security findings.

## Reporting a Vulnerability

- Do not open public GitHub issues for suspected vulnerabilities.
- Instead, open a private Security Advisory in GitHub (Security > Advisories) or email the maintainers if applicable.
- Include clear reproduction steps, affected paths/files, and any known CVEs or rule IDs.

## Our Triage Process

Operational triage for automated scanners (Gitleaks, Trivy, CodeQL) is documented in `docs/security/SECURITY_TRIAGE.md`.

High level steps:
- Validate the finding and collect evidence links (SARIF or logs).
- Classify severity and impacted assets.
- Assign an owner and agree on the fix path (remove secret/rotate, upgrade/patch, configuration change, or risk acceptance with compensating controls).
- Track remediation to closure and verify after the fix.

## Severity and Target SLAs

- Critical: fix or mitigation within 24–72 hours
- High: fix or mitigation within 7 days
- Medium: fix or mitigation within 30 days
- Low/Informational: best-effort or next maintenance window

## Scope

This policy covers vulnerabilities discovered in this repository and artifacts built from it. If you find issues in dependencies, please report upstream as well.
