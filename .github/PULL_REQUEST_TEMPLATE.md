## Summary

Describe the change and why it’s needed.

## Checklist

- [ ] I ran the Skills Smoke tests locally or via CI
  - Command: `Invoke-Pester -Path tests/Skills.Smoke.Tests.ps1 -CI`
- [ ] Governance metrics JSON included if touching critical paths (cloudrun/, gcp/, nova-stack/, ops/, platform/, infra/, services/, nova-backend-db/, observability/, security/, governance/policies/)
  - Add a file under `governance/metrics/<ticket-or-pr>.<yyyy-mm-dd>.json`
- [ ] Tests added/updated as needed
- [ ] Documentation updated (README/docs) as needed
- [ ] No secrets or sensitive data included

## Links

- Issue/Ticket:
- Related PRs:

## Notes

Anything reviewers should be aware of (risk, rollout plan, etc.).