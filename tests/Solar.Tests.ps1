# Creators: Tyler McKendry & Nova
# Pester smoke tests (v1, Pester v3-compatible)
$root = "C:\Nova"

Describe "Nova Solar Scaffolds" {
  It "has bots directory" {
    (Test-Path (Join-Path $root "bots")) | Should Be $true
  }
  It "has exactly 18 entities" {
    ((Get-ChildItem (Join-Path $root "bots") -Directory).Count) | Should Be 18
  }
  It "has solar_map.json" {
    (Test-Path (Join-Path $root "ops\solar_map.json")) | Should Be $true
  }
}
