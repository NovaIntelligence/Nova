Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Skills Smoke Tests' {
    It 'Cold Caller generates outreach artifacts and summary' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $csv = Join-Path $repoRoot 'samples/skills/sample-leads.csv'
        Test-Path $csv | Should -BeTrue

        $outDir = Join-Path $env:TEMP ("nova_skills_out_" + (Get-Date -Format 'yyyyMMddHHmmssfff'))
        & (Join-Path $repoRoot 'tools/skills/Outbound-Deal-Machine.ps1') -LeadsCsv $csv -OutDir $outDir -Channel 'email'

        $summary = Join-Path $outDir 'summary.json'
        $emailsDir = Join-Path $outDir 'outreach_emails'
        $next = Join-Path $outDir 'next_actions.csv'

        Test-Path $summary | Should -BeTrue
        Test-Path $emailsDir | Should -BeTrue
        (Get-ChildItem -Path $emailsDir -Filter *.txt).Count | Should -BeGreaterThan 0
        Test-Path $next | Should -BeTrue

        $js = Get-Content -Path $summary -Raw | ConvertFrom-Json
        [int]$js.emails_written | Should -BeGreaterThan 0

        Remove-Item -Recurse -Force $outDir
    }

    It 'Self-Sufficiency Model writes report with expected fields' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $outDir = Join-Path $env:TEMP ("nova_ssm_out_" + (Get-Date -Format 'yyyyMMddHHmmssfff'))
        & (Join-Path $repoRoot 'tools/skills/Self-Sufficiency-Model.ps1') -OutDir $outDir -InfraMonthlyCost 200 -AvgDealValue 1500 -CloseRate 0.2 -MeetingsPerWeek 10
        $report = Join-Path $outDir 'self_sufficiency_report.json'
        Test-Path $report | Should -BeTrue
        $js = Get-Content -Path $report -Raw | ConvertFrom-Json
        [int]$js.outputs.DealsToBreakEven | Should -BeGreaterThan 0
        [int]$js.outputs.MeetingsToBreakEven | Should -BeGreaterThan 0
        [double]$js.outputs.WeeksToBreakEven | Should -BeGreaterThan 0
        Remove-Item -Recurse -Force $outDir
    }
}
