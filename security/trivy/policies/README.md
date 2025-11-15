This folder holds optional Rego policies for Trivy config scans.

- Default: no policies are applied by the workflow.
- To enable, set an env or input and pass `--ignore-policy security/trivy/policies` to Trivy config scans.
- Start with extremely conservative ignores. Document the rationale for every rule.
