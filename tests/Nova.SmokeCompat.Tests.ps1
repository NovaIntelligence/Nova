Describe "Nova Smoke (Compat pinned)" {
  It "PowerShell version is >= 5" {
    if ($PSVersionTable.PSVersion.Major -lt 5) { throw "Detected PowerShell $($PSVersionTable.PSVersion). Require >= 5." }
  }
  It "Quality ledger dir exists" {
    if (-not (Test-Path "C:\Nova\gov\ledgers\quality")) { throw "Missing directory: C:\Nova\gov\ledgers\quality" }
  }
}