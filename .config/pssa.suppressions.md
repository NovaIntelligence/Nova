PSScriptAnalyzer suppressions guidance

Use targeted suppressions only when a rule is noisy or deeply intentional.

Options:
- Inline attribute on functions/params:
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Term used intentionally for user-facing skill name')]
  param()

- Scoped rule exclusion in CI (temporary): adjust `.config/pssa.settings.psd1` ExcludeRules for specific rules while you refactor.

Best practices:
- Prefer fixing code to match rules.
- Limit suppressions to the smallest scope.
- Always include a clear justification.
