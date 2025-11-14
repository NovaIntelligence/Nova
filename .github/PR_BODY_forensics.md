Summary
- Add Pester smoke test that exercises ip_provenance and validates artifacts (hashes, run.log, summary.json)
- Harden tools/forensics/Run-WalletRecoveryChecklist.ps1 (invoke ip_provenance directly; avoid clobbering logs; maintain manifest + hashes)
- Add tools/ip_provenance.ps1 stub to produce run.log and summary.json with SHA256 per input artifact
- Add GitHub Actions workflow (.github/workflows/forensics-smoke.yml) running the Pester suite on push/PR (Windows)
- README: document the Colab quick streaming helper usage for Ollama clients
- .gitignore: ignore forensic/intake/cases/ledger artifacts, .terraform, and tools/artifacts/

Notes
- Clean branch without restored DR artifacts; only intended test, script, workflow, and docs changes included.
- Local Pester run passed (2/2). CI should validate the checklist end-to-end.

Next Steps
- After merge, wire ip_provenance to the real tool and expand fixtures.
