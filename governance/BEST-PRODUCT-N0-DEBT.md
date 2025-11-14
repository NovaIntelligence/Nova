# Best Product, No Debt — Design Principles

These principles define how we build Nova. Each rule includes operational guardrails, measurable signals, and review checkpoints so it’s enforceable in code, CI, and process.

## 1) Quality > Cost-cutting

- Principle: Invest where outcomes are directly impacted (sales copy, strategy, negotiations, decision-quality). Save on bloat, not on intelligence.
- Guardrails:
  - Model Tiering: `tier=critical` tasks (copy, negotiation, pricing) must use the strongest approved model; `tier=noncritical` may use cheaper models.
  - SLOs: Define measurable conversion/quality SLOs per skill; a downgrade that violates SLOs is reverted automatically.
  - Perf/Spend Budgets: Track per-skill cost per output (CPO). CPO regression >15% with no outcome gain triggers revert.
- Signals:
  - `cvr`, `reply_rate`, `meetings_booked`, `A/B_win_rate`, `time_to_decision`.
  - `cost_per_email`, `cost_per_meeting`, `cost_per_deal`.
- Reviews:
  - PRs touching `tier=critical` code require “Quality Owner” review.
  - CI blocks deploys if SLO dashboards lack last-7d data.

## 2) Skills > Features

- Principle: Fewer, elite skills that generate measurable money beat buttons/features.
- Guardrails:
  - Skill Definition: Each skill has a spec with inputs, outputs, KPIs, SLOs, and an audit log.
  - Acceptance: New UI must attach to a skill contract; orphan UI is rejected.
  - Kill-switch: Any feature without 14-day revenue/time-saved evidence is disabled by default.
- Signals:
  - Weekly “money/impact per skill” report; feature-level metrics must map to a skill.
- Reviews:
  - PM sign-off requires KPI hypothesis and measurement plan pre-merge.

## 3) No Scale Before Proof

- Principle: Prove value before adding infra/automation.
- Guardrails:
  - Proof Bar: Skill must hit minimum thresholds (example defaults below) for 2 consecutive weeks:
    - Outbound: ≥ 10 qualified meetings/week at ≥ 10% reply rate
    - Copy: ≥ 5% lift in A/B vs. baseline with p<0.1
    - Capital Planner: At least one decision improved with projected ≥ 10x CPO ROI
  - Scale Gates: Infra (autoscaling, containers, queues) hidden behind feature flags until proof is met.
- Signals:
  - `proof_met: true|false` per skill; CI will fail a “scale” PR if `proof_met=false`.
- Reviews:
  - Attach last-14d KPI screenshot or artifact to scale PRs.

## 4) Debt-Free Growth

- Principle: Infra upgrades funded from Nova cash flow, not loans.
- Guardrails:
  - Upgrade Rule: `Δinfra_cost_month <= avg_monthly_profit_last_30d * 0.5` (or configurable cap).
  - Fail-Closed: CI blocks infra PRs if profitability artifact is missing or insufficient.
  - Rollback Plan: Each upgrade PR includes downgrade path and data retention plan.
- Signals:
  - `net_profit_30d`, `runway`, `break_even_meetings`, `break_even_deals`.
- Reviews:
  - Finance/Owner sign-off required for `Δinfra_cost_month > $250`.

---

## Implementation Notes

- Skill Contracts live under `skills/<skill>/spec.md` and `tools/skills/*.ps1` with structured inputs/outputs.
- KPI and cost artifacts are JSON in `artifacts/skills/<skill>/metrics/*.json` (CI uses these to block/allow PRs).
- Flags: Feature flags live in `config/flags/*.json`.

## Default Thresholds (v0.1)

- Outbound Deal Machine: reply_rate ≥ 10%, booking_rate ≥ 20% of replies, ≥ 10 qualified meetings/week.
- Offer & Copy: ≥ 5% absolute lift vs. control on primary conversion.
- Capital & Cashflow: Maintain ≥ 3 months runway; forbid negative NPV projects without explicit Owner override.
- Automation Builder: ≥ 10 human-hours saved/week with documented before/after.

## CI Hooks (v0.1)

- “Scale” or “Infra” labeled PRs must include `self_sufficiency_report.json` and last-14d KPI dump; otherwise fail.
- Pester smoke tests assert skill contracts produce outputs and metrics stubs.

## Ownership

- Quality Owner: Ensures model tiering and SLOs remain valid.
- Finance Owner: Ensures debt-free policy adherence and self-sufficiency math is attached to infra changes.
